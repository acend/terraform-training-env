terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.64.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.39.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

data "azurerm_subscription" "current" {}

data "azuread_client_config" "current" {}

# resource "azuread_group" "students" {
#   display_name            = "students"
#   description             = "students with cont. access to subscription"
#   owners                  = [data.azuread_client_config.current.object_id]
#   security_enabled        = true
#   prevent_duplicate_names = true
# }

data "azuread_group" "students" {
  display_name     = "students"
  security_enabled = true
}

resource "azurerm_role_assignment" "sub-contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Owner"
  principal_id         = data.azuread_group.students.id
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
  principal_id         = data.azuread_group.students.id
}

resource "azurerm_consumption_budget_subscription" "costlimit" {
  name            = "const-limit-budget"
  subscription_id = data.azurerm_subscription.current.id

  amount     = 500
  time_grain = "Monthly"

  time_period {
    start_date = "2023-08-01T00:00:00Z"
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
