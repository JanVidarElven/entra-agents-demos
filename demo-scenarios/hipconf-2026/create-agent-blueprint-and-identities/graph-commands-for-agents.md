# Microsoft Graph API Commands for Creating Agent Blueprints, Identities and Users

These commands can be used using Graph Explorer (https://aka.ms/ge), or any other REST API client for Agent Blueprints, Identities and Users.

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
  "displayName": "HIP Conf 2026 Agent Blueprint",
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

Using PowerShell Invoke-RestMethod, Postman client etc, run the following request and form values:

```http
POST https://login.microsoftonline.com/<my-tenant-id>/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

client_id=<agent-blueprint-id>
scope=https://graph.microsoft.com/.default
client_secret=<my-secret-credential>
grant_type=client_credentials
```

### Create the Agent Identity using the Token

Using PowerShell Invoke-RestMethod, Postman client etc, run the following request and the request body as shown below:

```http
POST /serviceprincipals/Microsoft.Graph.AgentIdentity
OData-Version: 4.0
Content-Type: application/json
Authorization: Bearer <token-from-agent-blueprint>
```

```json
{
    "displayName": "HIP Conf 2026 Agent Identity",
    "agentIdentityBlueprintId": "<my-agent-blueprint-id>",
    "sponsors@odata.bind": [
        "https://graph.microsoft.com/v1.0/users/<id>",
        "https://graph.microsoft.com/v1.0/groups/<group-id>"
    ]
}
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
  "displayName": "HIP Conf 2026 Agent User",
  "mailNickname": "hip-conf-2026.agent",
  "userPrincipalName": "hip-conf-2026.agent@<your-upn-suffix>",
  "identityParentId": "<agent-identity-id>"
}
```

## Admin Consent for Agent Identities

This last part is important if you want your Agent Identity be able to access API's like Microsoft Graph, MCP for Enterprise etc.

You can customize this URI with the correct tenant id, agent identity id, and any scopes, copy the uri and run this in your browser to bring up the admin consent. You can run this multiple times to add more scopes as needed.

```http
https://login.microsoftonline.com/<tenant-id>/v2.0/adminconsent?client_id=<agent-identity-id>&scope=User.Read&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123
```