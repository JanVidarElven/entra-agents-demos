// Application Insights - Bicep module
// Created by - Jan Vidar Elven

@description('The Azure region where all resources in this module should be created')
param location string

@description('A list of tags to apply to the resources')
param resourceTags object

@description('The name of the application insights to create. Max 24 characters.')
param appInsightsResourceName string

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsResourceName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    SamplingPercentage: json('100.0')
    IngestionMode: 'ApplicationInsights'
  }
}

output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

