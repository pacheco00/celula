# =============================================================================
# variables.tf
# Declaración de todas las variables del proyecto con tipos, defaults y
# descripciones detalladas. Centralizar variables aquí facilita la
# reutilización del código para distintos entornos (dev, staging, prod).
# =============================================================================

# -----------------------------------------------------------------------------
# VARIABLES DE AZURE / GENERAL
# -----------------------------------------------------------------------------
variable "resource_group_name" {
  type        = string
  description = "Nombre del Resource Group que contendrá todos los recursos del proyecto."
  default     = "rg-aks-nginx-demo"
}

variable "location" {
  type        = string
  description = <<-EOT
    Región de Azure donde se desplegarán los recursos.
    Usa el formato corto de Azure: "eastus", "westeurope", "eastus2", etc.
    Todos los recursos se crean en la misma región para minimizar latencia y costos.
  EOT
  default     = "eastus2"
}

variable "prefix" {
  type        = string
  description = <<-EOT
    Prefijo que se antepone al nombre de todos los recursos.
    Útil para identificar recursos por proyecto/entorno.
    Ejemplo: "myapp-prod", "demo", "corp-staging"
  EOT
  default     = "demo"
}

variable "tags" {
  type        = map(string)
  description = "Mapa de etiquetas aplicadas a todos los recursos para gobernanza y facturación."
  default = {
    Environment = "demo"
    Project     = "aks-nginx-ilb"
    ManagedBy   = "Terraform"
    Owner       = "DevOps Team"
  }
}

# -----------------------------------------------------------------------------
# VARIABLES DE RED
# IMPORTANTE: Los rangos de IP no deben solaparse entre sí ni con redes
# on-premises si hay conectividad VPN/ExpressRoute.
#
# Ejemplo de distribución de IPs en este proyecto:
#   VNet:           10.0.0.0/16  → 65534 IPs disponibles
#   AKS Nodes:      10.0.0.0/22  → 1022 IPs (nodos + pods con Azure CNI)
#   ILB Subnet:     10.0.4.0/27  → 30 IPs (solo para el Load Balancer)
#   Kubernetes SVC: 10.100.0.0/16 → 65534 ClusterIPs para Services
# -----------------------------------------------------------------------------
variable "vnet_address_space" {
  type        = string
  description = "Espacio de direcciones (CIDR) de la Virtual Network principal."
  default     = "10.0.0.0/16"
}

variable "aks_subnet_cidr" {
  type        = string
  description = <<-EOT
    CIDR de la subnet donde se desplegarán los NODOS de AKS.
    Con Azure CNI, cada pod consume una IP de esta subnet, así que
    debe ser lo suficientemente grande:
      - Calcular: (max_nodes × max_pods_per_node) + buffer
      - Ejemplo: 10 nodos × 30 pods = 300 IPs mínimo → usar /22 (1022 IPs)
  EOT
  default     = "10.0.0.0/22"
}

variable "ilb_subnet_cidr" {
  type        = string
  description = <<-EOT
    CIDR de la subnet dedicada al Internal Load Balancer (ILB).
    El ILB recibirá una IP privada de este rango.
    /27 (30 IPs) es más que suficiente para este propósito.
  EOT
  default     = "10.0.4.0/27"
}

variable "service_cidr" {
  type        = string
  description = <<-EOT
    Rango de IPs reservado para Kubernetes Services (ClusterIP, NodePort).
    CRÍTICO: No debe solaparse con la VNet ni con ninguna red enrutada
    en el entorno corporativo. Es un rango "virtual" que solo existe dentro
    del plano de control de Kubernetes.
  EOT
  default     = "10.100.0.0/16"
}

variable "dns_service_ip" {
  type        = string
  description = <<-EOT
    IP del servicio DNS interno de Kubernetes (CoreDNS).
    Debe ser una IP DENTRO de service_cidr.
    Convencionalmente se usa la décima IP del rango (ej: 10.100.0.10).
    Esta IP es la que usan los pods para resolver nombres DNS internos.
  EOT
  default     = "10.100.0.10"
}

# -----------------------------------------------------------------------------
# VARIABLES DE AKS
# -----------------------------------------------------------------------------
variable "kubernetes_version" {
  type        = string
  description = <<-EOT
    Versión de Kubernetes a instalar.
    Consultar versiones disponibles con:
      az aks get-versions --location eastus2 --output table
    Siempre usar una versión soportada (dentro de las últimas 3 minor versions).
  EOT
  default     = "1.29"
}

variable "node_vm_size" {
  type        = string
  description = <<-EOT
    Tamaño de VM para los nodos del pool por defecto.
    Guía de selección:
      - Desarrollo/Demo:   Standard_D2s_v3  (2 vCPU, 8 GB RAM)
      - Cargas moderadas:  Standard_D4s_v3  (4 vCPU, 16 GB RAM)
      - Cargas intensas:   Standard_D8s_v3  (8 vCPU, 32 GB RAM)
    Usar VMs de la familia 'Ds' o 'Bs' para soporte de Premium SSD.
  EOT
  default     = "Standard_D2s_v3"
}

variable "node_initial_count" {
  type        = number
  description = <<-EOT
    Número inicial de nodos al crear el clúster.
    Debe ser >= node_min_count y <= node_max_count.
    Después de la creación, el autoscaler gestiona el conteo.
  EOT
  default     = 2
}

variable "node_min_count" {
  type        = number
  description = <<-EOT
    Número MÍNIMO de nodos que el Cluster Autoscaler puede mantener.
    El autoscaler NUNCA reducirá por debajo de este valor, incluso si
    los nodos están totalmente ociosos.
    Recomendación: mínimo 2 para alta disponibilidad.
  EOT
  default     = 2
}

variable "node_max_count" {
  type        = number
  description = <<-EOT
    Número MÁXIMO de nodos a los que el Cluster Autoscaler puede escalar.
    Limita el gasto máximo en infraestructura.
    El autoscaler escala hasta este límite cuando hay pods en estado Pending.
  EOT
  default     = 5
}

# -----------------------------------------------------------------------------
# VARIABLES DE NGINX INGRESS
# -----------------------------------------------------------------------------
variable "nginx_helm_chart_version" {
  type        = string
  description = <<-EOT
    Versión del Helm chart 'ingress-nginx' de Kubernetes.
    Consultar versiones disponibles en:
      https://github.com/kubernetes/ingress-nginx/releases
    o con: helm search repo ingress-nginx/ingress-nginx --versions
  EOT
  default     = "4.10.1"
}

variable "nginx_namespace" {
  type        = string
  description = <<-EOT
    Namespace de Kubernetes donde se instalará NGINX Ingress Controller.
    Best practice: usar un namespace dedicado para separar el ingress
    de los workloads de aplicación.
  EOT
  default     = "ingress-nginx"
}

variable "nginx_replica_count" {
  type        = number
  description = <<-EOT
    Número de réplicas del pod NGINX Ingress Controller.
    Recomendación: mínimo 2 para alta disponibilidad.
    Distribuir en distintos nodos con topologySpreadConstraints o
    pod anti-affinity (configurado en helm_values).
  EOT
  default     = 2
}

variable "ilb_ip_address" {
  type        = string
  description = <<-EOT
    IP privada estática asignada al Internal Load Balancer.
    DEBE estar dentro del rango de ilb_subnet_cidr.
    Especificarla explícitamente evita que Azure asigne una IP diferente
    en cada redeploy (lo cual rompería registros DNS internos, firewalls, etc.).
    
    Ejemplo: si ilb_subnet_cidr = "10.0.4.0/27", 
    IPs válidas: 10.0.4.4 - 10.0.4.30 (Azure reserva .0, .1, .2, .3, .31)
  EOT
  default     = "10.0.4.10"
}
