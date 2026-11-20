# Stack wrapper around units/key-vault: passes its values through.
#
# Consumer snippet (live/<env>/terragrunt.stack.hcl) - see README:
#   stack "keyvault" {
#     source                  = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//stacks/key-vault?ref=v1.2.0"
#     path                    = "keyvault"
#     no_dot_terragrunt_stack = true
#     values = {
#       unit_source = "git::https://github.com/traviscloud-com/cloud-platform-catalog-example.git//units/key-vault?ref=v1.2.0"
#       ...
#     }
#   }
#
# `unit_source` is a value and the unit sits at path "." for the reasons given
# in stacks/local-cluster/terragrunt.stack.hcl: the unit must be generated into
# the directory the consumer's stack block names, so the state key is the
# consumer's choice. Consequence: this stack must contain exactly one unit.

unit "key_vault" {
  source = values.unit_source
  path   = "."

  # Generate into <stack dir>/<path>, not <stack dir>/.terragrunt-stack/<path>.
  no_dot_terragrunt_stack = true

  values = {
    name                             = values.name
    location                         = values.location
    resource_group_name              = values.resource_group_name
    create_resource_group            = try(values.create_resource_group, true)
    officer_service_principal_names  = try(values.officer_service_principal_names, ["gh-cloud-platform-deploy"])
    reader_service_principal_names   = try(values.reader_service_principal_names, ["gh-cloud-platform-plan"])
    additional_officer_principal_ids = try(values.additional_officer_principal_ids, [])
    secrets_user_principals          = try(values.secrets_user_principals, {})
    generated_secrets                = try(values.generated_secrets, {})
    operator_managed_secret_names    = try(values.operator_managed_secret_names, [])
    purge_protection_enabled         = try(values.purge_protection_enabled, false)
    soft_delete_retention_days       = try(values.soft_delete_retention_days, 7)
    tags                             = try(values.tags, {})
  }
}
