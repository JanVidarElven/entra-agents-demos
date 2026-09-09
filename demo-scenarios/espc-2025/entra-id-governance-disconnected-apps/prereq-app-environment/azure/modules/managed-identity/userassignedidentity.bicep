// Azure User Assigned Managed Identity - Bicep module
// Created by - Jan Vidar Elven

@description('The name of the user assigned managed identity')
param userassignedIdentityName string

@description('The Azure region where all resources in this module should be created')
param location string

@description('A list of tags to apply to the resources')
param resourceTags object

resource userManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userassignedIdentityName
  location: location
  tags: resourceTags
}

output resourceId string = userManagedIdentity.id
output principalId string = userManagedIdentity.properties.principalId
output clientId string = userManagedIdentity.properties.clientId
