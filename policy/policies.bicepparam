using './policies.bicep'

// -----------------------------------------------------------------------------
// FILL / CONFIRM THESE. Defaults work, but set the region list to match yours.
// -----------------------------------------------------------------------------

// 1. Regions you actually want to allow. Anything else gets DENIED at deploy time.
//    Use the short form (eastus, canadacentral), not "East US".
param allowedLocations = [
  'eastus'
  'canadacentral'
]

// 2. The tag you want enforced, and the default value when it's missing.
param tagName  = 'costCenter'
param tagValue = 'unassigned'

// Optional:
// param policyIdentityLocation = 'eastus'
