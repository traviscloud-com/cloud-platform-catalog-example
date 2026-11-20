# Generic wrapper around modules/hub of cloud-platform-modules-example: one regional
# hub (VNet, optional firewall / DNS resolver / bastion, optional peering to
# another hub).
#
# Consumers never include this file; they instantiate it through a `unit`
# block (see README), which generates a directory containing a terragrunt.hcl
# that points here plus a terragrunt.values.hcl. Everything consumer-specific
# arrives through `values`, which use the key names of the platform's env.hcl
# and region.hcl so a consumer can pass `merge(env, region, {...})`.
#
# The consumer's tree must provide root.hcl (remote_state + provider).

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  # Peering to another hub is on when the consumer names that hub's unit.
  peer_hub_path = try(values.peer_hub_path, null)
}

terraform {
  # Bump the ref to adopt a new module release, then cut a new catalog tag.
  source = "git::https://github.com/traviscloud-com/cloud-platform-modules-example.git//modules/hub?ref=hub/v1.0.0"
}

# Only for the environment's central private DNS zone ID (enable_private_dns).
dependency "platform_network" {
  config_path = try(values.platform_network_path, "../../../platform/network")

  # Shape must match the consumer's platform-network outputs exactly
  # (cloud-platform-infra-example modules/platform-network/outputs.tf).
  mock_outputs = {
    ipam_pool_ids        = {}
    ipam_pool_prefixes   = {}
    network_group_ids    = {}
    network_manager_id   = null
    private_dns_zone_ids = {}
    root_pool_ids        = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "remote_hub" {
  enabled     = local.peer_hub_path != null
  config_path = local.peer_hub_path != null ? local.peer_hub_path : "../hub-peer-disabled"

  # Shape must match modules/hub/outputs.tf of the pinned module tag exactly.
  mock_outputs = {
    dns_resolver_inbound_ip = null
    firewall_private_ip     = null
    location                = "mockregion"
    resource_group_name     = "mock-rg-hub-remote"
    vnet_id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg-hub-remote/providers/Microsoft.Network/virtualNetworks/mock-vnet-hub-remote"
    vnet_name               = "mock-vnet-hub-remote"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

exclude {
  if      = try(values.excluded, false)
  actions = ["all"]
}

inputs = {
  environment       = values.environment
  location          = values.location
  region_short      = values.region_short
  address_space     = values.hub_address_space
  enable_firewall   = try(values.enable_firewall, false)
  firewall_sku_tier = try(values.firewall_sku_tier, "Basic")
  enable_telemetry  = try(values.enable_telemetry, false)

  # Stamps egress through this firewall -> it needs the AKS egress rules.
  aks_egress_via_firewall = try(values.aks_outbound_type, "loadBalancer") == "userDefinedRouting"
  firewall_route_entries  = try(values.firewall_route_entries, [])

  # Optional hub services, all default off.
  enable_dns_resolver = try(values.enable_dns_resolver, false)
  enable_bastion      = try(values.enable_bastion, false)
  bastion_sku         = try(values.bastion_sku, "Basic")
  private_dns_zone_id = try(values.enable_private_dns, false) ? lookup(dependency.platform_network.outputs.private_dns_zone_ids, values.environment, null) : null

  peer_hub = local.peer_hub_path == null ? null : {
    vnet_id             = dependency.remote_hub.outputs.vnet_id
    vnet_name           = dependency.remote_hub.outputs.vnet_name
    resource_group_name = dependency.remote_hub.outputs.resource_group_name
  }

  tags = try(values.tags, {})
}
