# Generic wrapper around modules/local-cluster of cloud-platform-modules-example: the
# Azure footprint of an external (non-Azure) environment - resource group,
# Key Vault, External Secrets Operator principal, optional container registry
# and blob storage.
#
# Consumers never include this file; they instantiate it through a `unit` or
# `stack` block (see README), which generates a directory containing a
# terragrunt.hcl that points here plus a terragrunt.values.hcl. Everything
# consumer-specific arrives through `values`.
#
# The consumer's tree must provide root.hcl (remote_state + provider).

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # Double slash: the module uses sibling sources (../service-principal, ...),
  # so the whole repository must be fetched. Bump the ref to adopt a new
  # module release, then cut a new catalog tag.
  source = "git::https://github.com/traviscloud-com/cloud-platform-modules-example.git//modules/local-cluster?ref=local-cluster/v1.1.0"
}

dependency "dns_principals" {
  # Path of the public-dns-principals unit, relative to the generated unit dir.
  config_path = try(values.dns_principals_path, "../../../platform/dns-principals")

  # Shape must match the consumer's public-dns-principals outputs exactly
  # (cloud-platform-infra-example modules/public-dns-principals/outputs.tf).
  # Empty maps = no DNS secrets yet (skipped until that unit is applied).
  mock_outputs = {
    azure_json            = {}
    client_ids            = {}
    client_secrets        = {}
    object_ids            = {}
    secret_end_dates      = {}
    tenant_id             = null
    zone_names            = {}
    zone_resource_groups  = {}
    zone_subscription_ids = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  environment = values.environment
  location    = values.location
  name_prefix = try(values.name_prefix, "demo")

  dns_secrets_present = contains(keys(dependency.dns_principals.outputs.client_ids), values.environment)
  dns_azure_json      = lookup(dependency.dns_principals.outputs.azure_json, values.environment, "")
  dns_sp_secret       = lookup(dependency.dns_principals.outputs.client_secrets, values.environment, "")

  secret_rotation_days          = try(values.secret_rotation_days, 730)
  owner_service_principal_names = try(values.owner_service_principal_names, ["gh-cloud-platform-deploy"])

  enable_acr            = try(values.enable_acr, false)
  acr_push_repositories = try(values.acr_push_repositories, {})
  acr_pull_repositories = try(values.acr_pull_repositories, null)

  enable_storage         = try(values.enable_storage, false)
  storage_containers     = try(values.storage_containers, [])
  storage_retention_days = try(values.storage_retention_days, 90)

  tags = try(values.tags, {})
}
