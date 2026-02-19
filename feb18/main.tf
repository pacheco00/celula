terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.38.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.3"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "2582c624-5631-45e8-848b-8f4b7cdd6490"
}

## Resource Group ##

data "azurerm_resource_group" "rg" {
  name = "rg-cloud-lab"
}

## Variables ##

variable "location" {
  type    = string
  default = "eastus"
}

variable "vm_size" {
  description = "Tamaño de VM de los nodos"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "node_count" {
  description = "Número de nodos del pool por defecto"
  type        = number
  default     = 1
}

# ─── ACR ────────────────────────────────────────────────────────────────────────

resource "azurerm_container_registry" "acr" {
  name                = "acre00"                          # Solo letras y números, único globalmente
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "Basic"                           # Basic | Standard | Premium
  admin_enabled       = false                             # Se usará el role assignment, no admin user
}

# Otorga al kubelet identity del AKS el rol AcrPull sobre el ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

# ─── Network ────────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "vnet-aks" {
  name                = "vnet-aks-e00"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.50.0.0/16"]
}

resource "azurerm_subnet" "snet-aks" {
  name                              = "snet-aks-e00"
  resource_group_name               = data.azurerm_resource_group.rg.name
  virtual_network_name              = azurerm_virtual_network.vnet-aks.name
  address_prefixes                  = ["10.50.0.0/24"]
  private_endpoint_network_policies = "Enabled"
}

# ─── AKS ────────────────────────────────────────────────────────────────────────

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-e00"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = "aks-dns-e00"

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
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = "10.100.110.0/24"
    dns_service_ip    = "10.100.110.10"
  }

  role_based_access_control_enabled = true
  local_account_disabled            = false

  depends_on = [azurerm_virtual_network.vnet-aks, azurerm_subnet.snet-aks]
}

resource "azurerm_kubernetes_cluster_node_pool" "workloads" {
  name                  = "poolapps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_DS2_v2"
  node_count            = 1
  vnet_subnet_id        = azurerm_subnet.snet-aks.id
  zones                 = []
  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

# ─── Outputs útiles ─────────────────────────────────────────────────────────────

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "aks_kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}