# Miniature of cloud-platform-infra-example/live/root.hcl for the offline fixture:
# LOCAL backend, key derived from path_relative_to_include(), azurerm provider
# without a subscription. No Azure access of any kind.
locals {
  unit_path = path_relative_to_include()
  unit_name = basename(local.unit_path)
}

remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_terragrunt_dir()}/.fixture-state/${path_relative_to_include()}/terraform.tfstate"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDER
    provider "azurerm" {
      features {}
      resource_provider_registrations = "none"
      storage_use_azuread             = true
    }
  PROVIDER
}

# Exposed so scripts/test-fixture.sh can assert the state key.
generate "state_key" {
  path      = "state-key.txt"
  if_exists = "overwrite_terragrunt"
  contents  = "${path_relative_to_include()}\n"
}
