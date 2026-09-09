// CosmosDB Container - Bicep module
// Created by - Jan Vidar Elven

@description('The name of the Cosmos DB account.')
param accountName string

@description('The name of the Cosmos DB container to create.')
param containerName string

@description('The name of the Cosmos DB database to create the container in.')
param databaseName string

/* resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-05-01-preview' existing = {
  name: databaseName
}
 */
resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2025-05-01-preview' = {
  name: '${accountName}/${databaseName}/${containerName}'
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/_etag/?'
          }
        ]
      }
    }
  }
}
