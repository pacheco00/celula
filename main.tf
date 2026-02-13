/*resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}
*/

data "azurerm_resource_group" "rg" {
  name = var.rg_name
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = [var.vnet_cidr]
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "snet_aks" {
  name                 = var.subnet_aks_name
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_aks_cidr]
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = "${var.aks_name}-dns"

  kubernetes_version = var.k8s_version

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_size
    enable_auto_scaling  = true
    min_count            = var.min_nodes
    max_count            = var.max_nodes
    node_count           = var.node_count
    vnet_subnet_id       = azurerm_subnet.snet_aks.id
    orchestrator_version = var.k8s_version
    type                 = "VirtualMachineScaleSets"
    # mode                 = "System"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure" # Recomendado para ILB + Service type LoadBalancer
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  azure_policy_enabled = true

  # Habilita integración con AAD si te interesa
  role_based_access_control_enabled = true

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count
    ]
  }
}

# Dar permisos de Network Contributor a la identidad del AKS en la subnet (para crear ILB interno)
data "azurerm_subscription" "current" {}

resource "azurerm_role_assignment" "aks_netcontrib" {
  scope                = azurerm_subnet.snet_aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}
