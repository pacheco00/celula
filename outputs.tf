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

data "azurerm_resource_group" "rg-cloud-lab" {
  name = "rg-cloud-lab"
}

resource "azurerm_virtual_network" "vnet-est00" {
  name                = "vnet-est00"
  location            = data.azurerm_resource_group.rg-cloud-lab.location
  resource_group_name = data.azurerm_resource_group.rg-cloud-lab.name
  address_space       = ["10.0.0.0/16"]
}

