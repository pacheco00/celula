############################################
# PROVIDERS
############################################

provider "azurerm" {
  features {}
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

############################################
# VARIABLES
############################################

variable "location" {
  type    = string
  default = "eastus"
}

variable "suffix" {
  type    = string
  default = "e00"
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "node_count" {
  type    = number
  default = 1
}

############################################
# RESOURCE GROUP
############################################

resource "azurerm_resource_group" "rg" {
  name     = "rg-cloud-lab"
  location = var.location
}

############################################
# NETWORK
############################################

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-aks-${var.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.100.0.0/16"]
}

resource "azurerm_subnet" "snet_aks" {
  name                 = "snet-aks-${var.suffix}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.100.1.0/24"]

  delegation {
    name = "aks-delegation"
    service_delegation {
      name = "Microsoft.ContainerService/managedClusters"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

############################################
# USER ASSIGNED IDENTITY
############################################

resource "azurerm_user_assigned_identity" "aks_uai" {
  name                = "uai-aks-${var.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

############################################
# ROLE ASSIGNMENTS (PERMISOS MÍNIMOS)
############################################

# Permisos sobre la VNet
resource "azurerm_role_assignment" "aks_vnet_contributor" {
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_uai.principal_id
}

# Permisos sobre la Subnet
resource "azurerm_role_assignment" "aks_subnet_contributor" {
  scope                = azurerm_subnet.snet_aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_uai.principal_id
}

############################################
# AKS CLUSTER CON USER ASSIGNED IDENTITY
############################################

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${var.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-dns-${var.suffix}"

  default_node_pool {
    name                         = "systempool"
    vm_size                      = var.vm_size
    node_count                   = var.node_count
    type                         = "VirtualMachineScaleSets"
    only_critical_addons_enabled = true
    vnet_subnet_id               = azurerm_subnet.snet_aks.id
    max_pods                     = 30
  }

identity {
  type         = "UserAssigned"
  identity_ids = [azurerm_user_assigned_identity.aks_uai.id]
}

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = "10.100.110.0/24"
    dns_service_ip    = "10.100.110.10"
  }

  role_based_access_control_enabled = true
  local_account_disabled            = false

  depends_on = [
    azurerm_role_assignment.aks_vnet_contributor,
    azurerm_role_assignment.aks_subnet_contributor
  ]
}

############################################
# INGRESS-NGINX (HELM)
############################################

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.0"

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      controller = {
        replicaCount = 1

        nodeSelector = {
          agentpool = "systempool"
        }

        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/azure-load-balancer-internal"        = "true"
            "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = azurerm_subnet.snet_aks.name
            "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path" = "/healthz"
          }
        }
      }
    })
  ]

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}
