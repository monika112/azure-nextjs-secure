terraform {
  backend "azurerm" {
    resource_group_name  = "rg-nextweb-tfstate"
    storage_account_name = "stnextwebprod"
    container_name       = "tfstate"
    key                  = "nextjs/prod.tfstate"
    use_azuread_auth     = true
    use_cli = true
  }
}
