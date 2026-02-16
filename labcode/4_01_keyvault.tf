
############################
# 4_01_keyvault.tf
############################
data "azurerm_client_config" "current" {}
resource "azurerm_key_vault" "kv" {
  name                       = "kv-tcslab"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  enable_rbac_authorization  = true
}

data "azurerm_role_definition" "kv_secret_user" {
  name  = "Key Vault Secrets User"
  scope = azurerm_key_vault.kv.id
}

resource "azurerm_role_assignment" "apim_kv_secrets_user" {
  scope              = azurerm_key_vault.kv.id
  role_definition_id = data.azurerm_role_definition.kv_secret_user.role_definition_id
  principal_id       = "c7349be8-dbf2-4580-a895-c4d937f7afbf" # principalId de la MI de APIM
}