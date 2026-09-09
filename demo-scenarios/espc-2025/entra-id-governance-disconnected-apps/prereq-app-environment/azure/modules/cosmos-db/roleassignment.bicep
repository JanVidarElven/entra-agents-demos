// CosmosDB Role Assignment - Bicep module
// Created by - Jan Vidar Elven

@description('The name of your Cosmos DB Account')
param cosmosDbAccountName string

@description('Specifies the object ID of a user, service principal or security group in the Azure Active Directory tenant for the vault. The object ID must be unique for the list of access policies. Get it by using Get-AzADUser or Get-AzADServicePrincipal cmdlets.')
param objectId string
 
@description('Specifies the role the principal will get with the CosmosDB Account. Valid values are .')
@allowed([
  'Cosmos DB Built-in Data Reader'
  'Cosmos DB Built-in Data Contributor'
])
param roleName string

var roleIdMapping = {
  'Cosmos DB Built-in Data Reader': '00000000-0000-0000-0000-000000000001'
  'Cosmos DB Built-in Data Contributor': '00000000-0000-0000-0000-000000000002'
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2025-05-01-preview' existing = {
  name: cosmosDbAccountName
}


// Get the role definition ID for the specified role
// /subscriptions/aaaa0a0a-bb1b-cc2c-dd3d-eeeeee4e4e4e/resourceGroups/msdocs-identity-example/providers/Microsoft.DocumentDB/databaseAccounts/msdocs-identity-example-nosql/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002
resource roleDefinition 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2025-05-01-preview' existing = {
  name: roleIdMapping[roleName]
  parent: cosmosDbAccount
}

resource assignSqlRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-05-01-preview' = {
  name: guid(roleIdMapping[roleName], objectId, cosmosDbAccount.id)
  parent: cosmosDbAccount
  properties: {
    principalId: objectId
    roleDefinitionId: roleDefinition.id
    scope: cosmosDbAccount.id
  }
}

output roleDefinitionId string = roleDefinition.id
