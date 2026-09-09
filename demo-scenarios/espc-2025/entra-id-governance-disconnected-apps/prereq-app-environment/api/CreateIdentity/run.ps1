using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

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

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request to create a new identity."

# Generate new guid for id and current date time
$guid = New-Guid
$datetime = Get-Date

# Create a object to write the new identity to the database
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

# Push new identity to Cosmos DB
Push-OutputBinding -Name CosmosOutput -Value $identity

Write-Host ("Identity with Id " + $identity.id + " created successfully.")

$jsonResponse = $identity | ConvertTo-Json

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $jsonResponse
})
