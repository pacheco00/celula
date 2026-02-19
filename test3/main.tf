resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "devops-aks"

  # Configuración del grupo de máquinas (nodos)
  default_node_pool {
    name       = "default"
    vm_size    = var.node_vm_size

    # ✅ Autoscaler habilitado
    enable_auto_scaling = true
    min_count           = var.node_count_min
    max_count           = var.node_count_max
  }

  # Cómo se identifica el AKS ante Azure
  identity {
    type = "SystemAssigned"
  }

  # Red interna del clúster
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }
}

resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  # ⭐ La parte más importante: hacer el LoadBalancer PRIVADO (ILB)
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-internal"
    value = "true"
  }

  # Puerto HTTP
  set {
    name  = "controller.service.ports.http"
    value = "80"
  }

  # Puerto HTTPS
  set {
    name  = "controller.service.ports.https"
    value = "443"
  }

  # Esperar a que NGINX esté listo antes de continuar
  wait    = true
  timeout = 300

  # NGINX necesita que el AKS exista primero
  depends_on = [azurerm_kubernetes_cluster.aks]
}