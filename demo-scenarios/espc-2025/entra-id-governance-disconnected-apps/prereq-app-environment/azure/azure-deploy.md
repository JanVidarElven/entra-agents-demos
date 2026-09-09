# Azure Deployment for Elven Entra ID Outbound Provisioning Demo

The following are references to Bicep deployment stack for deploying required components for Elven Entra ID Outbound Provisioning Azure components:

- **Resource Group**. Resource container for all Elven Entra ID Outbound Provisioning Azure Resources.
- **Application Insights**. Application monitoring for the Function App.
- **Hosting Plan**. Hosting plan for the Function App. By default this will be created as a Consumption plan.
- **Storage Account**. Required storage account for the Function App.
- **Azure Function App**. The Function App for Elven Outbound Provisioning Web App that provides API functionality.
- **Managed Identity**. User Assigned Managed Identity for the Function App to access APIs and resources.

To deploy use this deployment guide instructions:

## Azure Login

You need to be logged into the target Azure environment and subscription.

```azurecli
az login --scope https://management.azure.com//.default --tenant <your-tenant>.onmicrosoft.com

az account set --subscription "<your-azure-subscription-id-or-name>"
```

## Azure Deployment Stack

We will be using Azure and Deployment Stack using Bicep.

```azurecli
az stack sub create --location NorwayEast --name "stack-elven-outbound-provisioning" --template-file .\main.bicep --deny-settings-mode none --action-on-unmanage deleteResources

az stack sub create --location NorwayEast --name "stack-elven-outbound-provisioning" --template-file .\main.bicep --parameters SOMEOPTIONALPARAMETER=false --deny-settings-mode none --action-on-unmanage deleteResources
```
