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
Write-Host "PowerShell HTTP trigger function processed a request to update a identity."

# Check id and get item to update
If ($Request.Params.id) {
    $identity = $CosmosInput | Where-Object { $_.id -eq $Request.Params.id}

    # Updating item values
    If ($Request.Body.name) {
        $identity.name = $Request.Body.name
    }
    If ($Request.Body.identity) {
        $identity.identity = $Request.Body.identity
    }
}
else {
    
}

Push-OutputBinding -Name CosmosOutput -Value $identity

$body = "Identity with Id " + $identity.id + " updated successfully."

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
