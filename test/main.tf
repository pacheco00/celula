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


## Network ##

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
  private_endpoint_network_policies = "Enabled" # Requerido por AKS Azure CNI
}

resource "azurerm_subnet" "snet-ingress" {
  name                 = "snet-ingress-e00"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet-aks.name
  address_prefixes     = ["10.50.1.0/24"]
}


## AKS ##

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
    network_plugin    = "azure" # Azure CNI
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = "10.100.100.0/24" #Es un rango virtual usado por Kubernetes para asignar IPs a los ClusterIP Services (servicios internos).
    dns_service_ip    = "10.100.100.10"
    #docker_bridge_cidr = "172.17.0.0/16"
  }

  role_based_access_control_enabled = true
  local_account_disabled            = false
  # tags       = { project = var.prefix }
  depends_on = [azurerm_virtual_network.vnet-aks, azurerm_subnet.snet-aks, azurerm_subnet.snet-ingress]
}
##apps nodepool
resource "azurerm_kubernetes_cluster_node_pool" "workloads" {
  name                  = "poolapps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_DS2_v2"
  node_count            = 1
  vnet_subnet_id        = azurerm_subnet.snet-aks.id   # "/subscriptions/2582c624-5631-45e8-848b-8f4b7cdd6490/resourceGroups/rg-demo-aks-dev/providers/Microsoft.Network/virtualNetworks/demo-aks-vnet/subnets/demo-aks-snet-aks"
  zones                 = []
  /*tags = {
    Environment = "dev"
  }*/
  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}


/*

resource "azurerm_kubernetes_cluster" "example" {
  name                = "example-aks1-e00"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = "exampleaks1"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.example.kube_config[0].client_certificate
  sensitive = true
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.example.kube_config_raw
  sensitive = true
}
*/