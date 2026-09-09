# Demo - Entra ID Protected API - Part 2

## Create App Registrations in Entra ID for Resource API and Client

Create two App Registrations in Entra ID for:

- Identities API, Single-Tenant
- Identities Client, Single-Tenant

In the Identities API, select to Expose an API, og set the App ID URI to something like api://identitiesapi.<your-verified-domain.com>.

Add scopes for:

- access_as_user (User and Admin Consent)
- Identities.Read (User and Admin Consent)
- Identities.ReadWrite (User and Admin Consent)
- Identities.ReadWrite.All (Admin Consent only)

In the Identities Client App Registration, add the API permissions for the Identities API, do not consent on behalf of organization.

Add Authentication Platforms for:

- Web and Postman Redirect URI: https://oauth.pstmn.io/v1/callback
- SPA and Redirect URI: http://localhost:3000

Make sure to support ID and Access Token for Implicit Flows.

## Add Module for Extracting JWT Token and Claims

```powershell
@{
    # For latest supported version, go to 'https://www.powershellgallery.com/packages/Az'.
    # To use the Az module in your function app, please uncomment the line below.
    'Az.Accounts' = '5.*'
    'JWTDetails' = '1.*'
}
```

## Add Authorization Logic to Functions

Add after Trigger:

```powershell
# BEGIN: TO-BE-ADDED-IN-DEMO
# Check if Authorization Header and get Access Token
$AuthHeader = $Request.Headers.'Authorization'
If ($AuthHeader) {
    $AuthHeader
    $parts = $AuthHeader.Split(" ")
    $accessToken = $parts[1]
    $jwt = $accessToken | Get-JWTDetails

    Write-Host "This is an authorized request by $($jwt.name) [$($jwt.preferred_username)]"

    # Check Tenant Id to be another Azure AD Organization or Personal Microsoft
    If ($jwt.tid -eq "9188040d-6c67-4c5b-b112-36a304b66dad") {
        Write-Host "This is a Personal Microsoft Account"
    } else {
        Write-Host "This is a Work or School Account from Tenant ID : $($jwt.tid)"
    } 
}
# END: TO-BE-ADDED-IN-DEMO

```

For Get Identities, add after getting Cosmos DB Items:

```powershell
# BEGIN: TO-BE-ADDED-IN-SECOND-DEMO
If ($AuthHeader) {
    Write-Host "The Requesting User has the Scopes: $($jwt.scp)"
    # Check for Scopes and Authorize
    If ($jwt.scp -notcontains "Identities.ReadWrite.All") {
        Write-Host "User is only authorized to see own Identities!"
        # $Identities = $Identities | Where-Object {$_.uid -eq $jwt.oid}
        # $Identities = $Identities | Where-Object {$_.upn -eq $jwt.preferred_username }
        $Identities = $Identities | Where-Object {$_.name -eq $jwt.name}
    }
} else {
    Write-Host "No Auth, return nothing!"
    $Identities = $Identities | Where-Object {$_.id -eq $null}
}
# END: TO-BE-ADDED-IN-SECOND-DEMO
```

For Create Identity, add so that the Claims User Id and Upn are added to the document item:

```powershell
# Create a object to write the new whish to the database
$identity = [PSCustomObject]@{
    id = $guid.Guid
    name = $Request.Body.name
    identity = $Request.Body.identity
    pronoun = [PSCustomObject]@{ 
        name = $Request.Body.pronoun.name 
    }
    created = $datetime.ToString()
    uid = $jwt.oid
    upn = $jwt.preferred_username
}

```

## Set up Authentication in Postman using OAuth 2.0

Use the Client ID, Tenant ID and the Client Secret from the Client App Registration, and use Authorization Code Flow to get an access token for the Whishes API.

This Bearer token can now be added to the Authorization Header for Postman requests so that requests can be authorized.

## Publish Function App to Azure

The local Function App project can now be published to the Azure Function App, and are ready for requiring authentication.
