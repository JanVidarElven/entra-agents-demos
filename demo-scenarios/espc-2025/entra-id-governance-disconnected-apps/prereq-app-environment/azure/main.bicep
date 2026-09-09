// Main Bicep deployment file for Azure resources:
// Elven Entra ID Outbound Provisioning
// Created by: Jan Vidar Elven
// Last Updated: 28.11.2025

targetScope = 'subscription'

// Main Parameters for Deployment
// TODO: Change these to match your environment
param environment string = 'demo'
param applicationName string = 'entra-id-outbound-provisioning'
param customerName string = 'elven'
param customerShortName string = 'elven'
param location string = 'norwayeast'
param resourceGroupName string = 'rg-${applicationName}'

// Resource Tags for all resources deployed with this Bicep file
// TODO: Change these to match your environment
var defaultTags = {
  Environment: environment
  Application: '${applicationName}-${environment}'
  Dataclassification: 'Limited'
  Costcenter: 'IT'
  Criticality: 'Normal'
  Service: 'Elven Entra ID Outbound Provisioning'
  Deploymenttype: 'Bicep'
  Owner: 'Jan Vidar Elven'
  Business: 'Elven Organization'
}

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: defaultTags
} 

module userManagedIdentity 'modules/managed-identity/userassignedidentity.bicep' = {
  name: 'userAssignedManagementIdentity'
  scope: resourceGroup(rg.name)
  params: {
    location: location
    userassignedIdentityName: 'mi-${customerName}-${applicationName}'
    resourceTags: defaultTags
  }
}

var storageName = '${customerShortName}sa${take(replace(applicationName, '-', ''),17)}'

module blobStorage 'modules/storage-blob/storage.bicep' = {
  name: 'storage'
  scope: resourceGroup(rg.name)
  params: {
    location: location
    resourceTags: defaultTags
    storageName: storageName
  }
}

module instrumentation 'modules/application-insights/app-insights.bicep' = {
  name: 'instrumentation'
  scope: resourceGroup(rg.name)
  params: {
    location: location
    resourceTags: defaultTags
    appInsightsResourceName: 'appi-${customerName}-sec-${applicationName}'
  }
}

module appServicePlan 'modules/service-plan/serviceplan.bicep' = {
  name: 'servicePlan'
  scope: resourceGroup(rg.name)
  params: {
    location: location
    appServicePlanName: 'serviceplan-function-sec-${applicationName}'
    resourceTags: defaultTags
  }
}

var applicationEnvironmentVariables = [
  // You can add your custom environment variables here
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: instrumentation.outputs.appInsightsInstrumentationKey
        }
        {
          name: 'azure_subscription_id'
          value: subscription().subscriptionId
        }
        {
          name: 'entra_tenant_id'
          value: subscription().tenantId
        }
        {
          name: 'managedidentity_client_id'
          value: userManagedIdentity.outputs.clientId
        }                         
        {
          name: 'azure_storage_account_name'
          value: blobStorage.outputs.storageAccountName
        }
        {
          name: 'azure_storage_account_key'
          value: blobStorage.outputs.storageKey
        }
        {
          name: 'azure_storage_connectionstring'
          value: 'DefaultEndpointsProtocol=https;AccountName=${blobStorage.outputs.storageAccountName};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${blobStorage.outputs.storageKey}'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${blobStorage.outputs.storageAccountName};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${blobStorage.outputs.storageKey}'
        }         
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${blobStorage.outputs.storageAccountName};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${blobStorage.outputs.storageKey}'
        }      
  ]
  
module function 'modules/function/function.bicep' = {
  name: 'function'
  scope: resourceGroup(rg.name)
  params: {
    location: location
    functionAppName: '${customerName}-fa-sec-${replace(applicationName, 'elven-', '')}'
    resourceTags: defaultTags
    environmentVariables: applicationEnvironmentVariables
    appServicePlanId: appServicePlan.outputs.appServicePlanId
    identityId: userManagedIdentity.outputs.resourceId
  }
}

module cosmosDbAccount 'modules/cosmos-db/account.bicep' = {
  name: 'cosmosDbAccount'
  scope: resourceGroup(rg.name)
  params: {
    location: location
    resourceTags: defaultTags
    cosmosDbAccountName: 'cosmos-${customerName}-${applicationName}'
    enableFreeTier: false
    kind: 'GlobalDocumentDB'
  }
}

module cosmosDbDatabase 'modules/cosmos-db/database.bicep' = {
  name: 'cosmosDbDatabase'
  scope: resourceGroup(rg.name)
  params: {
    accountName: cosmosDbAccount.outputs.cosmosDbAccountName
    databaseName: 'db-outbound-provisioning'
  }
}

module container 'modules/cosmos-db/container.bicep' = {
  name: 'container'
  scope: resourceGroup(rg.name)
  params: {
    accountName: cosmosDbAccount.outputs.cosmosDbAccountName
    databaseName: cosmosDbDatabase.outputs.databaseName
    containerName: 'identities'
  }
}

module assignManagedIdentityCosmosDbRead 'modules/cosmos-db/roleassignment.bicep' = {
  name: 'roleAssignmentMICosmosDbRead'
  scope: resourceGroup(rg.name)
  params: {
    cosmosDbAccountName: cosmosDbAccount.outputs.cosmosDbAccountName
    roleName: 'Cosmos DB Built-in Data Reader'
    objectId: userManagedIdentity.outputs.principalId
  }
}

module assignManagedIdentityCosmosDbContributor 'modules/cosmos-db/roleassignment.bicep' = {
  name: 'roleAssignmentMICosmosDbContributor'
  scope: resourceGroup(rg.name)
  params: {
    cosmosDbAccountName: cosmosDbAccount.outputs.cosmosDbAccountName
    roleName: 'Cosmos DB Built-in Data Contributor'
    objectId: userManagedIdentity.outputs.principalId
  }
}

@description('Create a static web app')
module swaExternalIdentities 'br/public:avm/res/web/static-site:0.3.0' = {
  name: 'swa-outbound-provisioning'
  scope: resourceGroup(rg.name)
  params: {
    name: 'swa-${applicationName}'
    location: 'westeurope'
    sku: 'Standard'
  }
}

@description('Output the default hostname')
output endpoint string = swaExternalIdentities.outputs.defaultHostname

@description('Output the static web app name')
output staticWebAppName string = swaExternalIdentities.outputs.name
