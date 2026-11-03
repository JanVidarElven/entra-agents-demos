# Microsoft Graph API Commands for Creating Agent Blueprints, Identities and Users

These commands can be used using Graph Explorer [aka.ms/ge](https://aka.ms/ge), or any other REST API client for Agent Blueprints, Identities and Users.

Requires the Entra role assignment as Agent ID Administrator, Agent ID Developer.

## Agent Identity Blueprint

In Graph Explorer, prepare this request method, uri, and headers:

```http
POST /applications/microsoft.graph.agentIdentityBlueprint
OData-Version: 4.0
Content-Type: application/json
```

And add this request body:

```json
{
  "@odata.type": "Microsoft.Graph.AgentIdentityBlueprint",
  "displayName": "CIS 2026 Agent Blueprint",
  "sponsors@odata.bind": [
    "https://graph.microsoft.com/v1.0/users/<your-sponsor-user-object-id>"
  ],
  "owners@odata.bind": [
    "https://graph.microsoft.com/v1.0/users/<your-owner-user-object-id>"
  ]
}
```

## Agent Identity Blueprint Credentials

To let Agent Identities authenticate you either need to use Managed Identity or for local development or test use Client Secrets. Both options showed below:

### Managed Identity Federated Credentials

In Graph Explorer, prepare this request method, uri, and headers:

```http
POST /applications/<agent-blueprint-id>/microsoft.graph.agentIdentityBlueprint/federatedIdentityCredentials
OData-Version: 4.0
Content-Type: application/json
```

And add this request body, replacing the tenant id and principal id of your managed identity:

```json
{
    "name": "my-managed-identity",
    "issuer": "https://login.microsoftonline.com/<your-tenant-id>/v2.0",
    "subject": "<managed-identity-principal-id>",
    "audiences": [
        "api://AzureADTokenExchange"
    ]
}
```

### Client Secret Credentials

In Graph Explorer, prepare this request method, uri, and headers:

```http
POST /applications/<agent-blueprint-id>/microsoft.graph.agentIdentityBlueprint/addPassword
OData-Version: 4.0
Content-Type: application/json
```

And add this request body:

```json
{
  "passwordCredential": {
    "displayName": "My Secret",
    "endDateTime": "2026-12-10T23:59:59Z"
  }
}
```

## Add OAuth Scope for Agent Identity Blueprint

In Graph Explorer, prepare this request method, uri, and headers:

```http
PATCH /applications/<agent-blueprint-id>/microsoft.graph.agentIdentityBlueprint
OData-Version: 4.0
Content-Type: application/json
```

And add this request body, with a generated guid:

```json
{
    "identifierUris": ["api://<agent-blueprint-id>"],
    "api": {
      "oauth2PermissionScopes": [
        {
          "adminConsentDescription": "Allow the application to access the agent on behalf of the signed-in user.",
          "adminConsentDisplayName": "Access agent",
          "id": "<generate-a-guid>",
          "isEnabled": true,
          "type": "User",
          "value": "access_agent"
        }
      ]
  }
}
```

## Add Service Principal for Agent ID Blueprint

In Graph Explorer, prepare this request method, uri, and headers:

```http
POST /servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal
OData-Version: 4.0
Content-Type: application/json
```

And add this request body, using your blueprint app id created from above:

```json
{
  "appId": "<your-blueprint-app-id>"
}
```

## Create Agent Identity from Blueprint

To be able to create an Agent Identity from the Blueprint, we need to first authenticate using the Blueprint credentials, and then create an Agent Identity using that resulting access token. You can get an access token depending on if we are using Managed Identity or Client Secret, and then create the Agent Identity as show below.

### Get a Token using Managed Identity

Here we don't use Graph Explorer. Using Managed Identity, refer to the Microsoft Learn Docs for your Azure resource to get an token using the instance metadata service.

```http
GET http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=api://AzureADTokenExchange/.default
Metadata: True
```

Then, using PowerShell Invoke-RestMethod, Postman client etc, run the following request and form values:

```http
POST https://login.microsoftonline.com/<my-tenant-id>/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

client_id=<agent-blueprint-id>
scope=https://graph.microsoft.com/.default
client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
client_assertion=<msi-token>
grant_type=client_credentials
```

### Get a Token using Client Secret

#### Get a Token using Client Secret (REST API)

Send this form-encoded request directly to the Microsoft identity platform token endpoint:

```http
POST https://login.microsoftonline.com/<your-tenant-id>/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

client_id=<agent-blueprint-app-id>&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default&client_secret=<client-secret>&grant_type=client_credentials
```

Use the `access_token` from the response as the bearer token in the request below. Keep the client secret secure; do not include it in source control.

#### Get a Token using Client Secret with PowerShell

Use PowerShell Core. Set the client secret in the `AGENT_BLUEPRINT_CLIENT_SECRET` environment variable before running these commands:

```powershell
$TenantId = "<your-tenant-id>"
$AgentBlueprintId = "<agent-blueprint-app-id>"
$ClientSecret = $env:AGENT_BLUEPRINT_CLIENT_SECRET

if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
  throw "Set the AGENT_BLUEPRINT_CLIENT_SECRET environment variable first."
}

$TokenResponse = Invoke-RestMethod `
  -Method Post `
  -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
  -ContentType "application/x-www-form-urlencoded" `
  -Body @{
    client_id     = $AgentBlueprintId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $ClientSecret
    grant_type    = "client_credentials"
  }

$AccessToken = $TokenResponse.access_token
```

### Create the Agent Identity using the Token

#### Create the Agent Identity using the Token (REST API)

Send this request with the access token obtained above:

```http
POST https://graph.microsoft.com/v1.0/servicePrincipals/Microsoft.Graph.AgentIdentity
Authorization: Bearer <access-token>
OData-Version: 4.0
Content-Type: application/json

{
  "displayName": "CIS 2026 Agent Identity",
  "agentIdentityBlueprintId": "<agent-blueprint-app-id>",
  "sponsors@odata.bind": [
    "https://graph.microsoft.com/v1.0/users/<user-object-id>",
    "https://graph.microsoft.com/v1.0/groups/<group-id>"
  ]
}
```

#### Create the Agent Identity using the Token with PowerShell

Use the access token to create the agent identity:

```powershell
$AgentIdentityBody = @{
  displayName              = "CIS 2026 Agent Identity"
  agentIdentityBlueprintId = $AgentBlueprintId
  "sponsors@odata.bind"   = @(
    "https://graph.microsoft.com/v1.0/users/<user-object-id>"
    "https://graph.microsoft.com/v1.0/groups/<group-id>"
  )
}

$Headers = @{
  Authorization   = "Bearer $AccessToken"
  "OData-Version" = "4.0"
}

$AgentIdentity = Invoke-RestMethod `
  -Method Post `
  -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/Microsoft.Graph.AgentIdentity" `
  -Headers $Headers `
  -ContentType "application/json" `
  -Body ($AgentIdentityBody | ConvertTo-Json -Depth 5)

$AgentIdentity
```

## Create Agent User for Agent Identity (Optional)

In this request you can use Graph Explorer again for optionally creating an Agent User:

```http
POST https://graph.microsoft.com/v1.0/users/microsoft.graph.agentUser
Content-type: application/json
```

```json
{
  "accountEnabled": true,
  "displayName": "CIS 2026 Agent User",
  "mailNickname": "cis-2026.agent",
  "userPrincipalName": "cis-2026.agent@<your-upn-suffix>",
  "identityParentId": "<agent-identity-id>"
}
```

## Admin Consent for Agent Identities

This last part is important if you want your Agent Identity be able to access API's like Microsoft Graph, MCP for Enterprise etc.

You can customize this URI with the correct tenant id, agent identity id, and any scopes, copy the uri and run this in your browser to bring up the admin consent. You can run this multiple times to add more scopes as needed.

```http
https://login.microsoftonline.com/<tenant-id>/v2.0/adminconsent?client_id=<agent-identity-id>&scope=User.Read&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123
```
