// ---------------------------------------------------------------------------
// Secure, governed storage foundation - core infrastructure
//
// Deploys, in one resource group:
//   - a user-assigned managed identity (the storage account's Key Vault identity)
//   - a Key Vault (RBAC mode, soft-delete + purge protection) with an RSA key
//   - the RBAC grant that lets the identity unwrap that key
//   - a storage account encrypted with the customer-managed key (CMK)
//   - a blob container with versioning, soft delete, and a lifecycle rule
//   - a least-privilege data-plane role assignment for a human reader
//
// Deploy at resource-group scope:
//   az group create -n rg-secure-storage -l eastus
//   az deployment group create -g rg-secure-storage -f infra/main.bicep -p infra/main.bicepparam
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

// --- Parameters -------------------------------------------------------------

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Globally-unique storage account name (3-24 chars, lowercase + digits).')
param storageAccountName string

@description('Globally-unique Key Vault name (3-24 chars).')
param keyVaultName string

@description('Name of the user-assigned managed identity.')
param identityName string = 'mi-storage'

@description('Name of the RSA key used as the customer-managed key.')
param keyName string = 'cmk-storage'

@description('Name of the blob container to create.')
param containerName string = 'data'

@description('Storage redundancy SKU.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageSku string = 'Standard_GRS'

@description('Public IP allowed through the storage firewall (your current IP). Example: 203.0.113.10')
param allowedIpAddress string

@description('Entra object ID of the user who gets Storage Blob Data Reader on the account.')
param dataReaderPrincipalId string

// --- Built-in role definition IDs (constants) -------------------------------

// Key Vault Crypto Service Encryption User - lets a principal get/wrap/unwrap keys
// on behalf of a service (this is what the storage service needs to unwrap the DEK).
var cryptoEncryptionUserRoleId = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

// Storage Blob Data Reader - read blob DATA (data plane), not just see the account.
var blobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

// --- Managed identity -------------------------------------------------------

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

// --- Key Vault + key --------------------------------------------------------
// CMK on a storage account REQUIRES the vault to have soft-delete AND purge
// protection enabled - Azure refuses to wire CMK to a vault that can be wiped.

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
  }
}

resource cmkKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: keyName
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'wrapKey'
      'unwrapKey'
    ]
  }
}

// --- Grant: identity can unwrap the key on the vault ------------------------
// This is the permission half of CMK. Without it the storage account cannot
// configure encryption and the deployment of the account below will fail.

resource cryptoRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, identity.id, cryptoEncryptionUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cryptoEncryptionUserRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// --- Storage account with CMK ----------------------------------------------
// The account authenticates to Key Vault AS the user-assigned identity (the
// `identity` block under `encryption`) and uses the named key to wrap its DEK.
// dependsOn forces the role assignment to exist first - but note RBAC
// propagation can still lag, see README "Known limitations".

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: [
        {
          value: allowedIpAddress
          action: 'Allow'
        }
      ]
    }
    encryption: {
      identity: {
        userAssignedIdentity: identity.id
      }
      keySource: 'Microsoft.Keyvault'
      keyvaultproperties: {
        keyvaulturi: keyVault.properties.vaultUri
        keyname: cmkKey.name
      }
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
  }
  dependsOn: [
    cryptoRoleAssignment
  ]
}

// --- Blob service: versioning + soft delete ---------------------------------

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// --- Lifecycle management: hot -> cool -> archive -> delete -----------------

resource lifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  parent: storage
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          enabled: true
          name: 'tier-then-expire'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [
                'blockBlob'
              ]
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 30
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: 90
                }
                delete: {
                  daysAfterModificationGreaterThan: 365
                }
              }
            }
          }
        }
      ]
    }
  }
}

// --- Grant: a human gets data-plane read on the account --------------------
// Storage Blob Data Reader is a DATA-plane role: it lets this user read blob
// bytes. Control-plane Reader would show the account but NOT read the data.

resource blobReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, dataReaderPrincipalId, blobDataReaderRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataReaderRoleId)
    principalId: dataReaderPrincipalId
    principalType: 'User'
  }
}

// --- Outputs ----------------------------------------------------------------

output storageAccountId string = storage.id
output keyVaultUri string = keyVault.properties.vaultUri
output identityPrincipalId string = identity.properties.principalId
