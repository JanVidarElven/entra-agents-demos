using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata, $CosmosInput)

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
Write-Host "PowerShell HTTP trigger function processed a request to delete a identity."

# Check id and get item to delete
If ($Request.Params.id) {
    $identity = $CosmosInput | Where-Object { $_.id -eq $Request.Params.id}
}
else {
    
}

# Build the Document Uri for Cosmos DB REST API
$cosmosConnection = $env:ProtectedAPI_CosmosDB -replace ';',"`r`n" | ConvertFrom-StringData
$documentUri = $cosmosConnection.AccountEndpoint + "dbs/" + "db-outbound-provisioning" + "/colls/" + "identities" + "/docs/" + $identity.id

# Check if running with MSI (in Azure) or Interactive User (local VS Code)
If ($env:MSI_SECRET) {
    
    # Get Managed Service Identity from Function App Environment Settings
    $msiEndpoint = $env:MSI_ENDPOINT
    $msiSecret = $env:MSI_SECRET

    # Specify URI and Token AuthN Request Parameters
    $apiVersion = "2017-09-01"
    $resourceUri = "https://cosmos.azure.com"
    $tokenAuthUri = $msiEndpoint + "?resource=$resourceUri&api-version=$apiVersion"

    # Authenticate with MSI and get Token
    $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"="$msiSecret"} -Uri $tokenAuthUri
    $bearerToken = $tokenResponse.access_token
    Write-Host "Successfully retrieved Access Token Cosmos Document DB API using MSI."

} else {
    # Get Access Token for the interactively logged on user in local VS Code
    $accessToken = Get-AzAccessToken -TenantId elven.onmicrosoft.com -ResourceUrl "https://cosmos.azure.com"
    $bearerToken = $accessToken.Token
}

# Prepare the API request to delete the document item
$partitionKey = $identity.id
$headers = @{
    'Authorization' = 'type=aad&ver=1.0&sig='+$bearerToken
    'x-ms-version' = '2018-12-31'
    'x-ms-documentdb-partitionkey' = '["'+$partitionKey+'"]'
}

Invoke-RestMethod -Method Delete -Uri $documentUri -Headers $headers -SkipHeaderValidation

$body = "Identity with Id " + $identity.id + " deleted successfully."

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
