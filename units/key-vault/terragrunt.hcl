# Generic wrapper around modules/key-vault of cloud-platform-modules-example: one Key
# Vault (RBAC mode) with its resource group, Secrets Officer / Reader grants,
# generated secrets and operator-set placeholders. Used for an environment's
# secret store, which External Secrets Operator reads.
#
# Consumers never include this file; they instantiate it through a `unit` or
# `stack` block (see README), which generates a directory containing a
# terragrunt.hcl that points here plus a terragrunt.values.hcl. Everything
# consumer-specific arrives through `values`.
#
# The consumer's tree must provide root.hcl (remote_state + provider).
#
# Not exposed: the module's `managed_secrets` / `managed_secret_values`. Values
# are written to terragrunt.values.hcl in plain text, so a secret value must
# never travel through them. A consumer that needs Terraform-supplied secret
# values wraps the module itself (as modules/local-cluster does).

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # Bump the ref to adopt a new module release, then cut a new catalog tag.
  source = "git::https://github.com/traviscloud-com/cloud-platform-modules-example.git//modules/key-vault?ref=key-vault/v1.0.0"
}

inputs = {
  name                  = values.name
  location              = values.location
  resource_group_name   = values.resource_group_name
  create_resource_group = try(values.create_resource_group, true)

  officer_service_principal_names  = try(values.officer_service_principal_names, ["gh-cloud-platform-deploy"])
  reader_service_principal_names   = try(values.reader_service_principal_names, ["gh-cloud-platform-plan"])
  additional_officer_principal_ids = try(values.additional_officer_principal_ids, [])
  secrets_user_principals          = try(values.secrets_user_principals, {})

  generated_secrets             = try(values.generated_secrets, {})
  operator_managed_secret_names = try(values.operator_managed_secret_names, [])

  purge_protection_enabled   = try(values.purge_protection_enabled, false)
  soft_delete_retention_days = try(values.soft_delete_retention_days, 7)

  tags = try(values.tags, {})
}
