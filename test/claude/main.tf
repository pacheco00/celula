# =============================================================================
# main.tf
# Punto de entrada principal del proyecto. Orquesta todos los módulos y recursos.
# =============================================================================

# -----------------------------------------------------------------------------
# RESOURCE GROUP
# Contenedor lógico que agrupa todos los recursos de Azure.
# Todos los recursos del proyecto vivirán dentro de este grupo.
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

# -----------------------------------------------------------------------------
# VIRTUAL NETWORK
# Red virtual privada donde se desplegará el clúster AKS.
# Tener una VNet personalizada nos da control total sobre:
#   - Rangos de IP (address_space)
#   - Segmentación en subnets
#   - Integración con otros recursos de Azure (VPN, ExpressRoute, etc.)
# -----------------------------------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_address_space]

  tags = var.tags
}

# -----------------------------------------------------------------------------
# SUBNET PARA AKS (node_subnet)
# Subnet donde se desplegarán los NODOS del clúster (VMs).
# Importante:
#   - Debe tener suficiente espacio de IPs para nodos + pods (Azure CNI).
#   - Se delega implícitamente al servicio AKS.
#   - /22 = 1022 IPs disponibles (suficiente para escenarios medianos).
# -----------------------------------------------------------------------------
resource "azurerm_subnet" "aks_nodes" {
  name                 = "${var.prefix}-aks-nodes-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.aks_subnet_cidr]
}

# -----------------------------------------------------------------------------
# SUBNET PARA INTERNAL LOAD BALANCER (ILB)
# Subnet dedicada al ILB que usará NGINX Ingress.
# Separar el ILB en su propia subnet es una BEST PRACTICE porque:
#   - Permite aplicar NSGs específicos al tráfico de entrada.
#   - Facilita el control de acceso desde redes on-premises o peerings.
#   - Aísla el punto de entrada del tráfico interno de los nodos.
# La IP privada del ILB se asignará desde este rango.
# -----------------------------------------------------------------------------
resource "azurerm_subnet" "ilb" {
  name                 = "${var.prefix}-ilb-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.ilb_subnet_cidr]
}

# -----------------------------------------------------------------------------
# NETWORK SECURITY GROUP PARA NODOS AKS
# Firewall a nivel de subnet que controla el tráfico hacia/desde los nodos.
# Reglas mínimas requeridas para el funcionamiento de AKS.
# -----------------------------------------------------------------------------
resource "azurerm_network_security_group" "aks_nsg" {
  name                = "${var.prefix}-aks-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Regla: Permitir tráfico HTTPS interno (necesario para API Server y pods)
  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Regla: Permitir tráfico HTTP interno (necesario para health probes del ILB)
  security_rule {
    name                       = "allow-http-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Asociar el NSG a la subnet de nodos AKS
resource "azurerm_subnet_network_security_group_association" "aks_nsg_assoc" {
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks_nsg.id
}

# -----------------------------------------------------------------------------
# AZURE KUBERNETES SERVICE (AKS)
# El clúster Kubernetes gestionado de Azure.
# 
# Componentes clave configurados:
#   1. default_node_pool     → Pool de nodos con autoscaler
#   2. identity              → Identidad del clúster para gestionar recursos Azure
#   3. network_profile       → Configuración de red (Azure CNI)
#   4. oms_agent             → Integración con Azure Monitor / Log Analytics
#   5. auto_scaler_profile   → Comportamiento del Cluster Autoscaler
# -----------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # DNS prefix para el API Server del clúster.
  # La URL del API server será: <dns_prefix>-<hash>.hcp.<region>.azmk8s.io
  dns_prefix = "${var.prefix}-aks"

  # Versión de Kubernetes. Siempre especificarla explícitamente
  # para tener control sobre upgrades y evitar cambios inesperados.
  kubernetes_version = var.kubernetes_version

  # -------------------------------------------------------------------------
  # DEFAULT NODE POOL
  # Pool inicial y obligatorio del clúster. Hospeda los pods del sistema
  # (kube-system, gatekeeper, etc.) y los workloads de usuario si no se
  # crean pools adicionales.
  #
  # enable_auto_scaling = true  → Activa el Cluster Autoscaler de Kubernetes.
  #   El Cluster Autoscaler monitorea pods en estado "Pending" (sin nodo
  #   disponible) y escala UP automáticamente. También escala DOWN cuando
  #   nodos están subutilizados por más del umbral configurado.
  #
  # min_count / max_count → Límites de escalado.
  #   El autoscaler NUNCA bajará de min_count ni subirá de max_count.
  #   node_count inicial debe estar entre min y max.
  #
  # vnet_subnet_id → Coloca los nodos en nuestra subnet personalizada,
  #   necesario para que el ILB pueda estar en la misma VNet.
  # -------------------------------------------------------------------------
  default_node_pool {
    name                = "systempool"
    vm_size             = var.node_vm_size
    enable_auto_scaling = true
    min_count           = var.node_min_count
    max_count           = var.node_max_count
    node_count          = var.node_initial_count
    vnet_subnet_id      = azurerm_subnet.aks_nodes.id
    os_disk_size_gb     = 50
    os_disk_type        = "Managed"

    # Upgrade settings: controla cuántos nodos pueden estar no disponibles
    # durante un upgrade de Kubernetes.
    upgrade_settings {
      max_surge = "10%"
    }

    tags = var.tags
  }

  # -------------------------------------------------------------------------
  # IDENTITY
  # SystemAssigned = Azure crea y gestiona automáticamente una Managed Identity
  # para el clúster. Esta identidad se usa para:
  #   - Crear/gestionar Load Balancers, Public IPs, etc.
  #   - Leer secretos de Key Vault (si se configura).
  #   - Acceder a Container Registry (ACR).
  # Alternativa: UserAssigned (más control, requiere gestión manual).
  # -------------------------------------------------------------------------
  identity {
    type = "SystemAssigned"
  }

  # -------------------------------------------------------------------------
  # NETWORK PROFILE
  # Define cómo Kubernetes gestiona la red de pods y servicios.
  #
  # network_plugin = "azure" → Azure CNI (Container Network Interface).
  #   Cada pod obtiene una IP REAL de la subnet de Azure.
  #   Ventajas: pods directamente accesibles desde la VNet, mejor rendimiento.
  #   Desventaja: consume más IPs que kubenet.
  #
  # network_policy = "azure" → Azure Network Policy.
  #   Permite definir NetworkPolicies de Kubernetes para aislar tráfico entre pods.
  #
  # service_cidr → Rango de IPs para Kubernetes Services (ClusterIP).
  #   DEBE ser diferente a la VNet y no solaparse con nada en la red corporativa.
  #
  # dns_service_ip → IP del DNS interno de Kubernetes (CoreDNS).
  #   Debe estar DENTRO de service_cidr.
  #
  # load_balancer_sku = "standard" → REQUERIDO para ILB con AKS moderno.
  #   El SKU Standard soporta múltiples frontend IPs, availability zones, etc.
  # -------------------------------------------------------------------------
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    load_balancer_sku = "standard"
  }

  # -------------------------------------------------------------------------
  # CLUSTER AUTOSCALER PROFILE
  # Parámetros avanzados que controlan el COMPORTAMIENTO del autoscaler.
  # Estos valores son críticos para evitar over-scaling o under-scaling.
  #
  # balance_similar_node_groups:
  #   Si hay múltiples node pools similares, el autoscaler intenta mantener
  #   un balance equitativo entre ellos al escalar.
  #
  # expander = "random":
  #   Cuando hay que agregar nodos y hay múltiples opciones (node pools),
  #   elige aleatoriamente. Otras opciones: "least-waste", "most-pods", "priority".
  #
  # max_graceful_termination_sec:
  #   Tiempo máximo que el autoscaler espera para que un pod termine limpiamente
  #   antes de forzar la eliminación del nodo (scale-down).
  #
  # scale_down_delay_after_add:
  #   Tiempo de espera después de agregar un nodo antes de intentar escalar down.
  #   Evita "flapping" (escalar up/down repetidamente).
  #
  # scale_down_unneeded:
  #   Tiempo que un nodo debe estar "no necesario" antes de ser eliminado.
  #
  # scan_interval:
  #   Con qué frecuencia el autoscaler revisa si necesita escalar.
  #
  # skip_nodes_with_local_storage / skip_nodes_with_system_pods:
  #   Protecciones: el autoscaler NO eliminará nodos que tengan pods con
  #   almacenamiento local o pods del sistema (kube-system).
  # -------------------------------------------------------------------------
  auto_scaler_profile {
    balance_similar_node_groups      = false
    expander                         = "random"
    max_graceful_termination_sec     = 600
    max_node_provisioning_time       = "15m"
    max_unready_nodes                = 3
    max_unready_percentage           = 45
    new_pod_scale_up_delay           = "0s"
    scale_down_delay_after_add       = "10m"
    scale_down_delay_after_delete    = "10s"
    scale_down_delay_after_failure   = "3m"
    scale_down_unneeded              = "10m"
    scale_down_unready               = "20m"
    scale_down_utilization_threshold = "0.5"
    scan_interval                    = "10s"
    skip_nodes_with_local_storage    = true
    skip_nodes_with_system_pods      = true
  }

  # -------------------------------------------------------------------------
  # OMS AGENT (Azure Monitor para Containers)
  # Envía métricas y logs del clúster a Log Analytics Workspace.
  # Permite usar Container Insights en el portal de Azure para:
  #   - Ver métricas de CPU/memoria por nodo y pod.
  #   - Consultar logs con KQL (Kusto Query Language).
  #   - Configurar alertas automáticas.
  # -------------------------------------------------------------------------
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  # Deshabilitar dashboard HTTP (inseguro, no recomendado en producción)
  http_application_routing_enabled = false

  tags = var.tags

  # Dependencia explícita: AKS necesita la subnet antes de crearse
  depends_on = [
    azurerm_subnet_network_security_group_association.aks_nsg_assoc
  ]
}

# -----------------------------------------------------------------------------
# LOG ANALYTICS WORKSPACE
# Repositorio centralizado de logs y métricas para Azure Monitor.
# Requerido por el OMS Agent de AKS.
#
# retention_in_days: Días que se conservan los logs (mínimo 30, máximo 730).
# sku = "PerGB2018": El más común, se paga por GB ingestado.
# -----------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.prefix}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ROLE ASSIGNMENT: AKS → SUBNET
# La identidad del clúster AKS necesita permisos sobre la subnet para poder
# crear el Internal Load Balancer (ILB) dentro de ella.
#
# Rol "Network Contributor": permite crear/modificar recursos de red en la
# subnet, incluyendo:
#   - Crear Load Balancers
#   - Asignar IPs privadas
#   - Crear interfaces de red para los nodos
#
# scope: aplicado a TODA la VNet para que aplique también a la subnet del ILB.
# principal_id: la identidad del control plane de AKS (kubelet identity principal).
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}
