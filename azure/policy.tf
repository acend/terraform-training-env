resource "azurerm_subscription_policy_assignment" "location-policy" {
    display_name         = "Allowed locations"
    name                 = "location-policy"
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    subscription_id      = data.azurerm_subscription.current.id
    parameters           = <<PARAMS
{ "listOfAllowedLocations": { "value": ["westeurope"] } }
PARAMS
}

resource "azurerm_subscription_policy_assignment" "vm-size-policy" {
    display_name         = "Allowed virtual machine size SKUs"
    name                 = "vm-size-policy"
    policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3"
    subscription_id      = data.azurerm_subscription.current.id
    parameters           = <<PARAMS
{ "listOfAllowedSKUs": { "value": ["basic_a1", "basic_a2"] } }
PARAMS
}
