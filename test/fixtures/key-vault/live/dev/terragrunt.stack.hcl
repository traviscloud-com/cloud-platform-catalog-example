# Consumer side: instantiates the catalog's key-vault stack so that the unit
# lands at live/dev/keyvault (state key dev/keyvault). scripts/test-fixture.sh
# sets CATALOG_STACK_SOURCE / CATALOG_UNIT_SOURCE (working tree, or a pushed ref
# with CATALOG_REF); a real consumer hard-codes the pinned git URL (see README).
stack "keyvault" {
  source = get_env("CATALOG_STACK_SOURCE")
  path   = "keyvault"

  no_dot_terragrunt_stack = true

  values = {
    unit_source = get_env("CATALOG_UNIT_SOURCE")

    name                = "kv-demo-dev"
    resource_group_name = "rg-demo-dev-secrets"
    location            = "westus3"

    generated_secrets             = { oauth2_proxy_cookie_secret = "oauth2-proxy-cookie-secret" }
    operator_managed_secret_names = ["google-oauth-client-id", "google-oauth-client-secret"]

    tags = { Environment = "dev", ManagedBy = "Terragrunt" }
  }
}
