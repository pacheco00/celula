############################
# AKS (Azure CNI + Standard LB)
############################

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${var.suffix}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = "aks-dns-${var.suffix}"

  default_node_pool {
    name                         = "systempool"
    vm_size                      = var.vm_size
    node_count                   = var.node_count
    type                         = "VirtualMachineScaleSets"
    only_critical_addons_enabled = true
    vnet_subnet_id               = azurerm_subnet.snet-aks.id
    max_pods                     = 30
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity { type = "SystemAssigned" }

  network_profile {
    network_plugin    = "azure" # Azure CNI
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = "10.100.110.0/24" #Es un rango virtual usado por Kubernetes para asignar IPs a los ClusterIP Services (servicios internos).
    dns_service_ip    = "10.100.110.10"
    #docker_bridge_cidr = "172.17.0.0/16"
  }

  role_based_access_control_enabled = true
  local_account_disabled            = false

  #tags       = { project = var.prefix }
  depends_on = [azurerm_virtual_network.vnet-aks, azurerm_subnet.snet-aks]
}
##apps nodepool
resource "azurerm_kubernetes_cluster_node_pool" "workloads" {
  name                  = "poolapps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.vm_size
  node_count            = var.node_count
  vnet_subnet_id        = azurerm_subnet.snet-aks.id #"/subscriptions/2582c624-5631-45e8-848b-8f4b7cdd6490/resourceGroups/rg-demo-aks-dev/providers/Microsoft.Network/virtualNetworks/demo-aks-vnet/subnets/demo-aks-snet-aks"
  zones                 = []
  tags = {
    Environment = "dev"
  }

  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

# # Instalar ingress-nginx con Helm

/*
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  timeout          = 600
  wait             = true
  cleanup_on_fail  = false

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.0"

  values = [
    yamlencode({
      controller = {
        tolerations = [
          {
            key      = "CriticalAddonsOnly"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
        replicaCount = 2
        nodeSelector = {
          "agentpool" = "poolapps" # nombre user pool
        }
        # admissionWebhooks = {
        #  enabled = true
        #  patch   = { enabled = true }
        # }
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/azure-load-balancer-internal"        = "true" #LB privad demo-aks-snet-aks
            "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = "demo-aks-snet-aks"
            "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" : "/healthz"
          }
        }
      }
    })
  ]
  depends_on = [azurerm_kubernetes_cluster_node_pool.workloads]
}
*/

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.0"

  wait    = true
  timeout = 600

  cleanup_on_fail = false

  values = [
    yamlencode({
      controller = {
        replicaCount = 1

        nodeSelector = {
          agentpool = "poolapps"
        }

        tolerations = [
          {
            key      = "CriticalAddonsOnly"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]

        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/azure-load-balancer-internal"        = "true"
            "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = "snet-aks"
            # "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = "snet-aks # "azurerm_subnet.snet-aks" #"/subscriptions/2582c624-5631-45e8-848b-8f4b7cdd6490/resourceGroups/rg-cloud-lab/providers/Microsoft.Network/virtualNetworks/vnet-aks-e00/subnets/snet-aks-e00"
            "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" = "/healthz"
          }
        }
      }
    })
  ]

  depends_on = [
    azurerm_kubernetes_cluster.aks,          # ensure cluster is ready
    azurerm_kubernetes_cluster_node_pool.workloads
  ]
}
