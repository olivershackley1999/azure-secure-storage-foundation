// ---------------------------------------------------------------------------
// Governance guardrails - deployed at SUBSCRIPTION scope
//
//   1. Allowed locations  (built-in, DENY effect)  - blocks resource creation
//      outside an approved region list, at deploy time.
//   2. Ensure-tag         (custom,  MODIFY effect) - adds a required tag if it
//      is missing, AND can remediate resources that already exist.
//
// MODIFY is chosen over APPEND deliberately: Append only mutates the in-flight
// create/update request, so it can neither overwrite a wrong value nor touch
// resources that already exist. Modify can do both - it carries a managed
// identity holding Tag Contributor, and a remediation task sweeps existing
// resources under that identity. That is why the assignment below has an
// `identity` block and a role assignment, and the allowed-locations one does not.
//
// Deploy at subscription scope:
//   az deployment sub create -l eastus -f policy/policies.bicep -p policy/policies.bicepparam
// ---------------------------------------------------------------------------

targetScope = 'subscription'

// --- Parameters -------------------------------------------------------------

@description('Regions where resources may be created.')
param allowedLocations array = [
  'eastus'
  'canadacentral'
]

@description('Region for the Modify assignment identity (any valid region).')
param policyIdentityLocation string = 'eastus'

@description('Tag name to enforce.')
param tagName string = 'costCenter'

@description('Default value applied when the tag is missing.')
param tagValue string = 'unassigned'

// --- Built-in / role IDs (constants) ----------------------------------------

// Built-in "Allowed locations" policy definition.
var allowedLocationsDefId = tenantResourceId('Microsoft.Authorization/policyDefinitions', 'e56962a6-4747-49cd-b67b-bf8b01975c4c')

// Tag Contributor - least-privilege role for editing tags (used by remediation).
var tagContributorRoleId = '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'

// --- 1. Allowed locations (DENY) --------------------------------------------

resource allowedLocationsAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'allowed-locations'
  properties: {
    displayName: 'Allowed locations'
    policyDefinitionId: allowedLocationsDefId
    parameters: {
      listOfAllowedLocations: {
        value: allowedLocations
      }
    }
  }
}

// --- 2. Ensure-tag (MODIFY) -------------------------------------------------

resource ensureTagDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: 'ensure-tag-modify'
  properties: {
    policyType: 'Custom'
    mode: 'Indexed'
    displayName: 'Ensure ${tagName} tag exists (Modify)'
    description: 'Adds the ${tagName} tag with a default value when it is missing. Remediates existing resources.'
    policyRule: {
      if: {
        field: 'tags[\'${tagName}\']'
        exists: 'false'
      }
      then: {
        effect: 'modify'
        details: {
          roleDefinitionIds: [
            subscriptionResourceId('Microsoft.Authorization/roleDefinitions', tagContributorRoleId)
          ]
          operations: [
            {
              operation: 'addOrReplace'
              field: 'tags[\'${tagName}\']'
              value: tagValue
            }
          ]
        }
      }
    }
  }
}

resource ensureTagAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'ensure-tag'
  location: policyIdentityLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Ensure ${tagName} tag (Modify)'
    policyDefinitionId: ensureTagDefinition.id
  }
}

// Grant the assignment's identity the role it needs to write tags during remediation.
resource tagRemediationRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, ensureTagAssignment.id, tagContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', tagContributorRoleId)
    principalId: ensureTagAssignment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
