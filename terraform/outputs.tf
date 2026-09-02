output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "container_app_name" {
  value = azurerm_container_app.main.name
}

output "container_apps_environment_name" {
  value = azurerm_container_app_environment.main.name
}

output "container_registry_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "frontdoor_hostname" {
  value = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "container_app_private_fqdn" {
  value = azurerm_container_app.main.ingress[0].fqdn
}

output "frontdoor_private_link_approval_command" {
  description = "Run after the first apply; AFD shared Private Link approval is not exposed declaratively by AzureRM."
  value       = "../scripts/approve-frontdoor-private-link.sh ${azurerm_resource_group.main.name} ${azurerm_container_app_environment.main.name}"
}
