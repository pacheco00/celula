terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tcsdevops-01"
    storage_account_name = "devtcstfstates"
    container_name       = "tcs-dev-container-tfstates"
    key                  = "azu-demolab-dev_op.tfstate"
  }
}