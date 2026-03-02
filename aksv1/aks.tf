############################
# ACR
############################

resource "azurerm_container_registry" "acr" {
  name                = "acr${var.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "Standard"
  admin_enabled       = false
}


resource "null_resource" "import_image" {
  provisioner "local-exec" {
    command = "az acr import --name ${azurerm_container_registry.acr.name} --source docker.io/pacheco00/lab-app:v2 --image lab.app:v2 --username pacheco00 --password ${var.dockerhub_token}"
  }

  depends_on = [azurerm_container_registry.acr]
}


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
/*
############################################
# ROLE ASSIGNMENTS (FIX AuthorizationFailed)
############################################

# Permisos sobre la VNet
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_virtual_network.vnet-aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id

  depends_on = [
    azurerm_kubernetes_cluster.aks

  ]
}

# Permisos sobre la Subnet
resource "azurerm_role_assignment" "aks_subnet_network_contributor" {
  scope                = azurerm_subnet.snet-aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}
*/

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

# ROLE AcrPull al AKS

/*
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_container_registry.acr
  ]
}
*/

# # Instalar ingress-nginx con Helm

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
            "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = "snet-aks-e00"
            "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" = "/healthz"
          }
        }
      }
    })
  ]

  depends_on = [
    azurerm_kubernetes_cluster.aks, # ensure cluster is ready
    azurerm_kubernetes_cluster_node_pool.workloads
  ]
}


############################################
# DEPLOYMENT
############################################
/*
resource "kubernetes_deployment" "lab_app" {
  metadata {
    name      = "lab-app"
    namespace = "default"
    labels = {
      app = "lab-app"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "lab-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "lab-app"
        }
      }

      spec {
        container {
          name  = "lab-app"
          image = "${azurerm_container_registry.acr.login_server}/lab.app:v1"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks #,
    #azurerm_role_assignment.aks_acr_pull
  ]
}

############################################
# SERVICE
############################################

resource "kubernetes_service" "lab_app_svc" {
  metadata {
    name      = "lab-app-svc"
    namespace = "default"
    labels = {
      app = "lab-app"
    }
  }

  spec {
    selector = {
      app = "lab-app"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }

  depends_on = [
    kubernetes_deployment.lab_app
  ]
}
*/