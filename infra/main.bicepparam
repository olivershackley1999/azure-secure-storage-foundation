using './main.bicep'

// -----------------------------------------------------------------------------
// FILL THESE IN. Everything else has a sensible default in main.bicep.
// -----------------------------------------------------------------------------

// 1. Globally-unique names (lowercase + digits for storage; 3-24 chars each).
//    Storage names must be unique across ALL of Azure, so add something random.
param storageAccountName = 'FILL_ME_saXXXXXX'
param keyVaultName       = 'FILL_ME_kvXXXXXX'

// 2. Your current public IP (so the storage firewall lets YOU through).
//    Find it: curl ifconfig.me   (or "what's my IP" in a browser)
param allowedIpAddress = 'FILL_ME_YOUR.PUBLIC.IP.ADDRESS'

// 3. Your Entra object ID (so you get Storage Blob Data Reader on the account).
//    Find it: az ad signed-in-user show --query id -o tsv
//    (or Entra ID -> Users -> you -> Object ID)
param dataReaderPrincipalId = 'FILL_ME_YOUR-ENTRA-OBJECT-ID'

// Optional overrides (defaults are fine to leave as-is):
// param location       = 'eastus'
// param storageSku     = 'Standard_GRS'
// param containerName  = 'data'
// param keyName        = 'cmk-storage'
// param identityName   = 'mi-storage'
