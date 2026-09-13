# azure-secure-storage-foundation

A secure, governed Azure storage account with a customer-managed encryption key,
least-privilege access, and policy guardrails. Built in the portal first, then
captured as Bicep.

Built while studying for the AZ-104. Stood it up by hand in the portal to learn the
wiring, then rewrote it as infrastructure-as-code so I can tear it down and rebuild
on demand.

## What it builds

- Key Vault in RBAC mode with soft delete and purge protection, holding a 2048-bit RSA key.
- User-assigned managed identity with Key Vault Crypto Service Encryption User on the vault.
- Storage account encrypted with the customer-managed key, blob public access off, firewall denying by default with a single allowed IP.
- Blob container with versioning, 7-day soft delete, and a lifecycle rule (cool at 30 days, archive at 90, delete at 365).
- Storage Blob Data Reader assignment for one user.
- Two subscription policies. Allowed-locations (deny) and a Modify policy that stamps a required tag and remediates existing resources.

## How it works

The storage service unwraps its data encryption key by authenticating to Key Vault
as the managed identity on every operation.

Blob access clears two independent gates. The data-plane role (Storage Blob Data
Reader) handles authorization, and the CMK unwrap handles decryption.

The tag policy uses Modify rather than Append so it can remediate resources that
already exist, which is why its assignment carries its own identity and Tag
Contributor role.

## Why I built it this way

- Customer-managed key so the encryption key is a switch the customer controls.
- Managed identity for the unwrap instead of a stored secret.
- Deny-by-default firewall with one allowed IP.
- Modify over Append on the tag policy so it works on existing resources, not just new writes.

## Deploy

Fill in the FILL_ME values in the two .bicepparam files first (storage and vault
names, your public IP, your Entra object ID).

```bash
# Core infrastructure
az group create -n rg-secure-storage -l eastus
az deployment group create -g rg-secure-storage -f infra/main.bicep -p infra/main.bicepparam

# Governance policies (subscription scope)
az deployment sub create -l eastus -f policy/policies.bicep -p policy/policies.bicepparam

# Tear down
az group delete -n rg-secure-storage --yes --no-wait
```

## What's next

- Turn off shared-key access so all access goes through Entra ID.
- Swap public endpoints and firewall for private endpoints.
- Automate the tag remediation trigger.

## Layout

```
infra/main.bicep         storage account, Key Vault, identity, role assignments
infra/main.bicepparam    fill-in values
policy/policies.bicep    allowed-locations + ensure-tag policies
policy/policies.bicepparam
```
