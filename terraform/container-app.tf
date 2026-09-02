resource "azurerm_container_app_environment" "main" {
  name                               = "cae-${local.prefix}"
  location                           = azurerm_resource_group.main.location
  resource_group_name                = azurerm_resource_group.main.name
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.main.id
  logs_destination                   = "log-analytics"
  infrastructure_resource_group_name = "rg-${local.prefix}-aca-infra"
  infrastructure_subnet_id           = azurerm_subnet.container_apps.id
  internal_load_balancer_enabled     = true
  public_network_access              = "Disabled"
  zone_redundancy_enabled            = true
  tags                               = local.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

# Internal DNS lets self-hosted deployment runners in the VNet resolve app and
# blue/green label hostnames. Front Door's managed Private Link handles its own DNS.
resource "azurerm_private_dns_zone" "container_apps" {
  name                = azurerm_container_app_environment.main.default_domain
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "container_apps" {
  name                 = "link-aca-${local.prefix}"
  private_dns_zone_id  = azurerm_private_dns_zone.container_apps.id
  virtual_network_id   = azurerm_virtual_network.main.id
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_private_dns_a_record" "container_apps_wildcard" {
  name                = "*"
  private_dns_zone_id = azurerm_private_dns_zone.container_apps.id
  ttl                 = 60
  records             = [azurerm_container_app_environment.main.static_ip_address]
  tags                = local.tags
}

resource "azurerm_container_app" "main" {
  name                         = "ca-${local.prefix}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Multiple"
  max_inactive_revisions       = 5
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  template {
    revision_suffix = "bootstrap"
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas

    container {
      name   = "web"
      image  = var.initial_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name  = "PORT"
        value = tostring(var.container_port)
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.main.connection_string
      }

      startup_probe {
        transport               = "HTTP"
        port                    = var.container_port
        path                    = var.liveness_probe_path
        interval_seconds        = 5
        timeout                 = 3
        failure_count_threshold = 30
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = var.container_port
        path                    = var.liveness_probe_path
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = var.container_port
        path                    = var.readiness_probe_path
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 3
        success_count_threshold = 1
      }
    }

    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = 50
    }
  }

  ingress {
    external_enabled           = true
    target_port                = var.container_port
    transport                  = "http"
    allow_insecure_connections = false

    traffic_weight {
      percentage      = 100
      latest_revision = true
      label           = "blue"
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.key_vault_secrets_user,
    azurerm_private_endpoint.acr,
    azurerm_private_endpoint.key_vault
  ]

  # Application releases are managed by the blue/green deployment pipeline.
  # This prevents a later infrastructure apply from undoing its image and traffic changes.
  lifecycle {
    ignore_changes = [
      template[0].revision_suffix,
      template[0].container[0].image,
      template[0].container[0].env,
      ingress[0].traffic_weight
    ]
  }
}
