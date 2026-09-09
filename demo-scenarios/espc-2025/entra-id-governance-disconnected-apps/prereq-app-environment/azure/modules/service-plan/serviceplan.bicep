// Azure App Service Plan - Bicep module
// Created by - Jan Vidar Elven

@description('The name of your app service plan')
param appServicePlanName string

@description('A list of tags to apply to the resources')
param resourceTags object

@description('The Azure region where all resources in this module should be created')
param location string

resource hostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
  }
}

output appServicePlanId string = hostingPlan.id
