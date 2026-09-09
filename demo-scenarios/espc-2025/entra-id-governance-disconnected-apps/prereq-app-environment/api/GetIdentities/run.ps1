using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata, $CosmosInput )

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
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host "Total number of identities: $($CosmosInput.count)"

If ($AuthHeader) {
    Write-Host "The Requesting User has the Scopes: $($jwt.scp)"
    # Check for Scopes and Authorize
    If ($jwt.scp -notcontains "Identity.ReadWrite.All") {
        Write-Host "User is only authorized to see own identities!"
        # $Identities = $Identities | Where-Object {$_.uid -eq $jwt.oid}
        # $Identities = $Identities | Where-Object {$_.upn -eq $jwt.preferred_username }
        $Identities = $Identities | Where-Object {$_.name -eq $jwt.name}
    }
} else {
    Write-Host "No Auth, return nothing!"
    $Identities = $Identities | Where-Object {$_.id -eq $null}
}

# Check if a specific id should be returned or all identities
If ($Request.Params.id) {
    # Get Identity by Id
    [array]$Identities = $CosmosInput | Where-Object { $_.id -eq $Request.Params.id}
}
else {
    # Get All Identities
    [array]$Identities = $CosmosInput
}

# Change the output (if needed) if there are not entries in the CosmosDB
if ($Identities.Count -eq 0) {
    $response = $Identities | Select-Object Id, Name, Identity, Pronoun, Created
}
else {
    $response = $Identities | Select-Object Id, Name, Identity, Pronoun, Created
}

$jsonResponse = ConvertTo-Json @($response)

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $jsonResponse
})
