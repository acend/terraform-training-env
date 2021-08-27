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
  role_definition_name = "Owner"
  principal_id         = azuread_group.students.id
}

resource "azurerm_resource_group" "dnszone" {
  name     = "setup-labz-dnszone"
  location = "West Europe"
}

resource "azurerm_dns_zone" "dnszone" {
  name                = "labz.ch"
  resource_group_name = azurerm_resource_group.dnszone.name
}

resource "azurerm_resource_group" "watcher" {
  name     = "setup-network-watcher"
  location = "West Europe"
}

resource "azurerm_network_watcher" "default" {
  name                = "nw-standard"
  location            = "West Europe"
  resource_group_name = azurerm_resource_group.watcher.name
}

output "nameserver" {
  description = "for external config"
  value       = azurerm_dns_zone.dnszone.name_servers
}

resource "azurerm_role_assignment" "dns-contributor" {
  scope                = azurerm_dns_zone.dnszone.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azuread_group.students.id
}

resource "azurerm_consumption_budget_subscription" "costlimit" {
  name            = "const-limit-budget"
  subscription_id = data.azurerm_subscription.current.subscription_id

  amount     = 500
  time_grain = "Monthly"

  time_period {
    start_date = "2021-08-01T00:00:00Z"
  }

  notification {
    enabled   = true
    threshold = 90.0
    operator  = "EqualTo"

    contact_emails = [
      "stream1@acend.ch",
    ]
  }

  notification {
    enabled   = false
    threshold = 100.0
    operator  = "GreaterThan"

    contact_emails = [
      "stream1@acend.ch",
    ]
  }
}
