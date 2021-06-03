terraform {
  required_version = ">= 0.15"

  required_providers {
    azurerm = ">= 2.59.0"
    random  = ">= 3.1.0"
    azuread = ">= 1.4.0"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "c1b34118-6a8f-4348-88c2-b0b1f7350f04"
}

provider "azuread" {}

data "azurerm_subscription" "current" {}

resource "azuread_group" "students" {
  display_name            = "students"
  description             = "students with cont. access to subscription"
  prevent_duplicate_names = true
}

resource "azurerm_role_assignment" "sub-contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.students.id
}

resource "azurerm_resource_group" "dnszone" {
  name     = "rg-labz-dnszone"
  location = "West Europe"
}

resource "azurerm_dns_zone" "dnszone" {
  name                = "azure.labz.ch"
  resource_group_name = azurerm_resource_group.dnszone.name
}

resource "azurerm_role_assignment" "dns-contributor" {
  scope                = azurerm_dns_zone.dnszone.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azuread_group.students.id
}
