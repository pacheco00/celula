##vnetaks
resource "azurerm_virtual_network" "vnetaks" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.40.0.0/16"]
  tags                = { project = var.prefix }
}

# Subred para los nodos/pods de AKS
resource "azurerm_subnet" "snet_aks" {
  name                 = "${var.prefix}-snet-aks"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnetaks.name
  address_prefixes     = ["10.40.1.0/24"]

  # Requerido por AKS Azure CNI
  #enforce_private_link_endpoint_network_policies = true
  private_endpoint_network_policies = "Enabled"
  #private_link_service_network_policies   = true

}

# Subred dedicada para el LB interno del Ingress

resource "azurerm_subnet" "snet_ingress" {
  name                 = "${var.prefix}-snet-ingress"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnetaks.name
  address_prefixes     = ["10.40.10.0/24"]
}
##vnet APIM

resource "azurerm_virtual_network" "vnetapim" {
  name                = "vnetapim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.kv_vnet_cidr
  tags                = { project = var.prefix }
}

resource "azurerm_subnet" "snet_apim" {
  name                 = "snet-apim"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnetapim.name
  address_prefixes     = var.kv_snet_apim_cidr
}

resource "azurerm_subnet" "kv_snet_pe" {
  name                 = "snet-pe-kv"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnetapim.name
  address_prefixes     = var.kv_snet_pe_cidr

  # Requerido para Private Endpoints
  private_endpoint_network_policies = "Disabled"
}

# Subred para Application Gateway
resource "azurerm_subnet" "snet_appgw" {
  name                 = "${var.prefix}-snet-appgw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnetapim.name
  address_prefixes     = var.kv_snet_appgw_cidr
}

