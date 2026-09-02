# Azure Next.js Secure Platform

Secure, production-oriented Azure infrastructure for deploying a **Next.js application on Azure Container Apps** using **Terraform**, **Azure Front Door Premium**, **Web Application Firewall**, private networking, Azure Container Registry, Key Vault, monitoring, remote Terraform state, and blue/green deployments.

---

## Architecture

```text
                           Internet
                              |
                              v
                    Azure Front Door Premium
                 +-----------------------------+
                 | HTTPS / TLS                 |
                 | Global Routing              |
                 | Web Application Firewall    |
                 | Rate Limiting               |
                 +-------------+---------------+
                               |
                               | HTTPS
                               v
                       Front Door Origin
                               |
                         Private Link
                               |
                               v
                Azure Container Apps Environment
              +-----------------------------------+
              |                                   |
              |       Next.js Container App       |
              |                                   |
              |   +---------------------------+   |
              |   | Blue Revision             |   |
              |   +---------------------------+   |
              |                                   |
              |   +---------------------------+   |
              |   | Green Revision            |   |
              |   +---------------------------+   |
              |                                   |
              +----------------+------------------+
                               |
          +--------------------+----------------------+
          |                    |                      |
          v                    v                      v
 Azure Container       Azure Key Vault        Azure Monitor
 Registry (ACR)                              / Log Analytics
                                                  |
                                                  v
                                         Application Insights
```

---

# Project Goals

This repository demonstrates how to deploy a secure Next.js workload on Azure using Infrastructure as Code.

The main goals are:

- Infrastructure provisioning with Terraform
- Next.js hosting on Azure Container Apps
- secure public entry through Azure Front Door Premium
- Web Application Firewall protection
- custom WAF rate limiting
- private connectivity to the Container App origin
- container images stored in Azure Container Registry
- secrets stored in Azure Key Vault
- managed identities instead of stored credentials
- application health endpoints
- Application Insights and Log Analytics monitoring
- Terraform remote state in Azure Blob Storage
- blue/green deployments using Container Apps revisions

---

# Azure Components

| Azure Service | Purpose |
|---|---|
| Azure Front Door Premium | Global HTTPS entry point and routing |
| Azure Web Application Firewall | Protects the application from malicious traffic |
| Azure Container Apps | Hosts the Next.js application |
| Azure Container Apps Environment | Provides runtime and networking environment |
| Azure Container Registry | Stores application container images |
| Azure Key Vault | Stores application secrets |
| Managed Identity | Passwordless Azure authentication |
| Virtual Network | Network isolation |
| Private DNS | Resolves private Container Apps endpoints |
| Azure Storage | Stores Terraform state |
| Log Analytics | Centralized infrastructure and application logs |
| Application Insights | Application telemetry and performance monitoring |

---

# Request Flow

```text
Browser
   |
   | HTTPS
   v
Azure Front Door Premium
   |
   | WAF inspection
   v
Front Door Route /*
   |
   v
Origin Group
   |
   | HTTPS
   v
Azure Container Apps
   |
   v
Next.js Application
```

Azure Front Door is intended to be the primary public entry point for the application.

---

# Repository Structure

```text
azure-nextjs-secure/
|
+-- app/
|   |
|   +-- api/
|       +-- health/
|           +-- live/
|           |   +-- route.ts
|           |
|           +-- ready/
|               +-- route.ts
|
+-- terraform/
|   +-- backend.tf
|   +-- providers.tf
|   +-- variables.tf
|   +-- outputs.tf
|   +-- networking.tf
|   +-- frontdoor.tf
|   +-- identity-acr-keyvault.tf
|   +-- monitoring.tf
|   +-- .gitignore
|   +-- ...
|
+-- README.md
```

The Terraform code is split by responsibility to keep the infrastructure easier to maintain and troubleshoot.

---

# Health Endpoints

The application exposes dedicated health endpoints through the Next.js App Router.

## Liveness Endpoint

File:

```text
app/api/health/live/route.ts
```

Example implementation:

```ts
export const dynamic = "force-dynamic";

export async function GET() {
  return Response.json(
    { status: "live" },
    { status: 200 }
  );
}
```

This creates:

```text
GET /api/health/live
```

Expected response:

```json
{
  "status": "live"
}
```

Expected HTTP status:

```text
200 OK
```

Example URL through Azure Front Door:

```text
https://<front-door-endpoint>.azurefd.net/api/health/live
```

---

## Readiness Endpoint

File:

```text
app/api/health/ready/route.ts
```

This creates:

```text
GET /api/health/ready
```

The readiness endpoint can be used to determine whether the application is ready to receive production traffic.

It can eventually validate dependencies such as:

- environment configuration
- database availability
- Azure Key Vault connectivity
- downstream APIs
- required services

---

# Why Health Endpoints Matter

The health endpoints can be used by:

- Azure Container Apps liveness probes
- Azure Container Apps readiness probes
- Azure Front Door health probes
- blue/green deployment validation
- CI/CD post-deployment verification
- monitoring and alerting

A typical deployment flow is:

```text
Deploy new revision
        |
        v
Call /api/health/live
        |
        v
Call /api/health/ready
        |
        v
Health checks pass
        |
        v
Shift production traffic
```

---

# Azure Front Door

Azure Front Door Premium provides:

- global HTTP and HTTPS routing
- TLS termination
- HTTPS redirects
- Web Application Firewall
- custom WAF rules
- managed WAF rules
- rate limiting
- origin health monitoring
- Private Link support
- integration with Azure Container Apps

A typical Front Door route resembles:

```hcl
resource "azurerm_cdn_frontdoor_route" "main" {
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id

  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.main.id
  ]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}
```

The origin should point to the Container App FQDN.

Example:

```hcl
host_name          = azurerm_container_app.main.ingress[0].fqdn
origin_host_header = azurerm_container_app.main.ingress[0].fqdn
```

---

# Azure Web Application Firewall

The WAF policy protects the application before traffic reaches Azure Container Apps.

The solution can include:

- managed security rules
- bot protection
- custom IP rules
- rate limiting
- application-layer protection

Example rate-limit rule:

```hcl
custom_rule {
  name                           = "GlobalRateLimit"
  enabled                        = true
  priority                       = 100
  type                           = "RateLimitRule"
  action                         = "Block"

  rate_limit_duration_in_minutes = 1
  rate_limit_threshold           = 1000

  match_condition {
    match_variable     = "RemoteAddr"
    operator           = "IPMatch"
    negation_condition = false

    match_values = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}
```

The threshold should be tuned based on observed production traffic.

---

# Azure Container Apps

The Next.js application is hosted in Azure Container Apps.

Container Apps provides:

- containerized application hosting
- revision-based deployments
- HTTP ingress
- automatic scaling
- health probes
- managed identity
- Azure Container Registry integration
- blue/green deployment support

Example:

```text
Azure Container Apps Environment
        |
        +-- Next.js Container App
              |
              +-- Blue Revision
              |
              +-- Green Revision
```

---

# Blue/Green Deployment

Azure Container Apps revisions can be used for blue/green deployments.

Initial state:

```text
Blue  -> 100%
Green ->   0%
```

Deploy the new version as Green:

```text
Blue  -> 100%
Green ->   0%
```

Validate:

```text
/api/health/live
/api/health/ready
```

Then gradually shift traffic:

```text
Blue  -> 90%
Green -> 10%
```

Then:

```text
Blue  -> 50%
Green -> 50%
```

Final state:

```text
Blue  ->   0%
Green -> 100%
```

The previous revision can remain available temporarily for rollback.

---

# Azure Container Registry

Application images are stored in Azure Container Registry.

Typical flow:

```text
Source Code
    |
    v
Docker Build
    |
    v
Azure Container Registry
    |
    v
Azure Container Apps
```

Managed identity should be preferred over registry passwords for image pulls.

---

# Azure Key Vault

Azure Key Vault is used to store sensitive application values.

Do not store secrets directly in:

```text
Terraform source code
terraform.tfvars
GitHub
Dockerfiles
container images
application source
```

Preferred pattern:

```text
Azure Container App
        |
        | Managed Identity
        v
Azure Key Vault
```

---

# Networking

The infrastructure uses Azure networking and private DNS.

Conceptually:

```text
Virtual Network
    |
    +-- Container Apps infrastructure
    |
    +-- Private Endpoint connectivity
    |
    +-- Private DNS
```

Azure Container Apps environment domains can resemble:

```text
<environment-id>.<region>.azurecontainerapps.io
```

Private DNS zones must be linked to the correct virtual network so private endpoints resolve correctly.

---

# Monitoring

The solution includes Azure monitoring services.

## Log Analytics

Used for:

- Container Apps logs
- revision troubleshooting
- infrastructure diagnostics
- centralized logging

## Application Insights

Used for:

- HTTP requests
- application failures
- response times
- dependencies
- application performance
- distributed tracing

Important metrics and events include:

```text
HTTP 4xx
HTTP 5xx
application exceptions
container restarts
failed revisions
CPU utilization
memory utilization
response latency
Front Door origin health
WAF blocks
rate-limit blocks
```

---

# Terraform Remote State

Terraform state is stored in Azure Blob Storage.

Recommended architecture:

```text
rg-nextweb-tfstate
     |
     +-- Storage Account
             |
             +-- tfstate
                    |
                    +-- nextjs/prod.tfstate
```

The main application infrastructure remains separate:

```text
rg-nextweb-prod
     |
     +-- Azure Front Door
     +-- WAF
     +-- Azure Container Apps
     +-- ACR
     +-- Key Vault
     +-- Networking
     +-- Monitoring
```

Separating Terraform state from the application resource group prevents an application `terraform destroy` from accidentally removing the backend that stores the state.

---

# Terraform Backend

Example:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-nextweb-tfstate"
    storage_account_name = "stnextwebprod"
    container_name       = "tfstate"
    key                  = "nextjs/prod.tfstate"

    use_azuread_auth = true
    use_cli          = true
  }
}
```

Microsoft Entra ID authentication is preferred over storage account keys.

The Terraform identity requires Blob data-plane access such as:

```text
Storage Blob Data Contributor
```

---

# Test Terraform State Access

```bash
az storage blob list \
  --account-name stnextwebprod \
  --container-name tfstate \
  --auth-mode login \
  --output table
```

If the command returns no rows and no error, the container is reachable but may simply be empty.

---

# Terraform State Security

Terraform state must not be committed to Git.

Recommended `.gitignore` entries:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
crash.log
.DS_Store
```

Do not commit:

```text
terraform.tfstate
terraform.tfstate.backup
storage account keys
SAS tokens
Azure client secrets
Key Vault secrets
.env files containing credentials
```

---

# Prerequisites

Install:

- Azure CLI
- Terraform
- Docker
- Git
- Node.js
- npm

Verify:

```bash
az version
terraform version
docker --version
git --version
node --version
npm --version
```

---

# Azure Login

Authenticate:

```bash
az login
```

Check the current subscription:

```bash
az account show --output table
```

Select the correct subscription if necessary:

```bash
az account set --subscription "<subscription-id>"
```

---

# Required Azure Resource Providers

The Azure subscription may require the following providers:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Cdn
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.ManagedIdentity
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Storage
```

Check provider status:

```bash
az provider list \
  --query "[?registrationState=='Registered'].namespace" \
  --output table
```

---

# Terraform Deployment

Navigate to the Terraform directory:

```bash
cd terraform
```

Initialize:

```bash
terraform init
```

If the backend changed:

```bash
terraform init -migrate-state
```

Format:

```bash
terraform fmt -recursive
```

Validate:

```bash
terraform validate
```

Plan:

```bash
terraform plan
```

Apply:

```bash
terraform apply
```

---

# Verify Azure Container App

Retrieve the Container App FQDN:

```bash
az containerapp show \
  --name ca-nextweb-prod \
  --resource-group rg-nextweb-prod \
  --query properties.configuration.ingress.fqdn \
  --output tsv
```

List revisions:

```bash
az containerapp revision list \
  --name ca-nextweb-prod \
  --resource-group rg-nextweb-prod \
  --output table
```

---

# Test Application Health

Test the Container App directly:

```bash
curl -i https://<container-app-fqdn>/api/health/live
```

Expected:

```text
HTTP 200
```

and:

```json
{"status":"live"}
```

Test readiness:

```bash
curl -i https://<container-app-fqdn>/api/health/ready
```

Then test through Azure Front Door:

```bash
curl -i https://<front-door-endpoint>.azurefd.net/api/health/live
```

and:

```bash
curl -i https://<front-door-endpoint>.azurefd.net/api/health/ready
```

---

# Troubleshooting

## Front Door returns 404

Verify:

```text
patterns_to_match = ["/*"]
link_to_default_domain = true
```

Also verify:

```text
origin hostname = Container App FQDN
origin host header = Container App FQDN
```

---

## Health endpoint returns 404

For Next.js App Router, the file location determines the URL.

This:

```text
app/api/health/live/route.ts
```

creates:

```text
/api/health/live
```

This:

```text
app/api/health/ready/route.ts
```

creates:

```text
/api/health/ready
```

A file named:

```text
app/health-live-route.ts
```

does not automatically create `/api/health/live`.

---

## Terraform backend returns 403

Verify RBAC:

```bash
az role assignment list \
  --assignee <principal-id> \
  --scope "<storage-account-resource-id>" \
  --include-inherited \
  --output table
```

Look for:

```text
Storage Blob Data Contributor
```

Then test Blob access directly.

---

# Suggested CI/CD Architecture

A future GitHub Actions pipeline can use OIDC instead of Azure client secrets.

```text
GitHub
   |
   v
GitHub Actions
   |
   | OIDC
   v
Microsoft Entra ID
   |
   v
Terraform
   |
   +--> Azure Infrastructure
   |
   +--> Docker Build
   |
   +--> Azure Container Registry
   |
   +--> Azure Container Apps
```

A production pipeline could perform:

```text
Pull Request
    |
    v
terraform fmt
    |
    v
terraform validate
    |
    v
Security Scan
    |
    v
terraform plan
    |
    v
Approval
    |
    v
terraform apply
    |
    v
Build Docker Image
    |
    v
Push to ACR
    |
    v
Deploy Green Revision
    |
    v
/api/health/live
/api/health/ready
    |
    v
Shift Traffic
    |
    v
Blue/Green Complete
```

---

# Future Improvements

Planned improvements can include:

- GitHub Actions CI/CD
- Azure OIDC authentication
- automated Terraform plans on pull requests
- production environment approvals
- custom domain
- managed TLS certificates
- additional WAF tuning
- Bot Manager rules
- Azure Monitor alerts
- Application Insights dashboards
- automated blue/green deployment
- automatic rollback
- Defender for Cloud
- container vulnerability scanning
- Checkov or tfsec
- Front Door diagnostic logs
- custom readiness dependency checks
- multi-region deployment

---

# Author

**Monika Mehrotra**

Cloud Architecture | Azure | DevOps | Terraform | Container Platforms | Application Architecture