
############################
# 4_02_apim.tf (CORREGIDO)
############################

resource "azurerm_network_security_group" "apim_nsg" {
  name                = "nsg-apim-${var.prefix}-${var.env}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name


  security_rule {
    name                       = "inbound-https-443"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443"] # portal/gateway
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "inbound-mgmt-3443"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443" # endpoint de mgmt
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }


  security_rule {
    name                       = "out-azurekeyvault-443"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureKeyVault"
  }

  security_rule {
    name                       = "out-storage-443"
    priority                   = 210
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "Storage"
  }

  security_rule {
    name                       = "out-azureactivedirectory-443"
    priority                   = 220
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureActiveDirectory"
  }

  tags = {
    project     = var.prefix
    environment = var.env
  }
}


resource "azurerm_subnet_network_security_group_association" "apim_subnet_nsg" {
  subnet_id                 = azurerm_subnet.snet_apim.id
  network_security_group_id = azurerm_network_security_group.apim_nsg.id
}


resource "azurerm_api_management" "apim" {
  name                = "${var.apim_name}-${var.prefix}-${var.env}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  publisher_name  = var.apim_publisher_name
  publisher_email = var.apim_publisher_email

  sku_name = "Developer_1"

  identity {
    type = "SystemAssigned"
  }

  virtual_network_type = "External"
  virtual_network_configuration {

    subnet_id = azurerm_subnet.snet_apim.id
  }

  tags = {
    project     = var.prefix
    environment = var.env
  }
  depends_on = [
    azurerm_subnet_network_security_group_association.apim_subnet_nsg
  ]
}
resource "azurerm_api_management_named_value" "nv_expected_api_key" {
  name                = "expected-api-key"
  display_name        = "expected-api-key"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  value               = "YOUR_VALUE" # o con Key Vault abajo
  secret              = true
  tags                = ["automation"]
}

output "apim_gateway_url" {
  value = azurerm_api_management.apim.gateway_url
}
