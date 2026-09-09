// CosmosDB Account - Bicep module
// Created by - Jan Vidar Elven

@description('The Azure region where all resources in this module should be created')
param location string

@description('A list of tags to apply to the resources')
param resourceTags object

@description('The name of the cosmos db account to create.')
param cosmosDbAccountName string

@description('If true, enable free tier (only once in organization)')
param enableFreeTier bool = false

@description('Kind of Cosmos DB account to create.')
param kind string = 'GlobalDocumentDB'

@description('The offer type for the Cosmos DB account. For example, "Standard".')
param offerType string = 'Standard'

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2025-05-01-preview' = {
  name: cosmosDbAccountName
  location: location
  tags: resourceTags
  kind: kind
  identity: {
    type: 'None'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    enableFreeTier: enableFreeTier
    minimalTlsVersion: 'Tls12' 
    databaseAccountOfferType: offerType
    cors: []
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capacityMode: 'Serverless'
  }
}

output cosmosDbAccountId string = cosmosDbAccount.id
output cosmosDbAccountName string = cosmosDbAccount.name


