// CosmosDB Database - Bicep module
// Created by - Jan Vidar Elven

@description('The database name for the Cosmos DB account.')
param databaseName string

@description('The account name for the Cosmos DB account.')
param accountName string

resource account 'Microsoft.DocumentDB/databaseAccounts@2025-05-01-preview' existing = {
  name: accountName
}
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-05-01-preview' = {
  parent: account
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

output databaseName string = database.name
