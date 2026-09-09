<#
.SYNOPSIS
    Opal Onboarding Script - Automates setup for resources required for Opal.

.DESCRIPTION
    PowerShell script for onboarding to Opal that automates:
    - Creating Service Principals for required applications
    - Setting up a dynamic Azure AD device group
    - Configuring Windows Cloud Login service principal for remote desktop access
    - Creating and assigning Microsoft Edge configuration policies
    - Validating existing setup

.PARAMETER Mode
    Operation mode: 'Setup' to run onboarding, 'Validate' to check existing setup
    Default: Setup

.EXAMPLE
    .\OpalOnboard.ps1
    Runs setup mode to create all resources

.EXAMPLE
    .\OpalOnboard.ps1 -WhatIf
    Preview what would be created without making changes

.EXAMPLE
    .\OpalOnboard.ps1 -Mode Validate
    Validates that all resources exist and are configured correctly

.NOTES
    Prerequisites:
    - Permissions: Application.ReadWrite.All, DeviceManagementConfiguration.ReadWrite.All, Group.ReadWrite.All, Directory.ReadWrite.All

    The script automatically installs required Microsoft Graph modules:
    - Microsoft.Graph.Authentication
    - Microsoft.Graph.Beta.Applications
    - Microsoft.Graph.Beta.DeviceManagement
    - Microsoft.Graph.Beta.Groups

    Setup Mode:
    - Connects to Microsoft Graph (interactive authentication)
    - Creates 8 Service Principals for required applications
    - Creates dynamic device group with membership rule
    - Configures Windows Cloud Login service principal:
      * Enables remote desktop protocol if not already enabled
      * Adds the device group to target device groups
    - Creates Edge configuration policy
    - Assigns policy to the device group

    WhatIf Mode:
    - Preview operations without making changes
    - Does not connect to Microsoft Graph
    - Shows what would be created
    - Only available in Setup mode

    Validate Mode:
    - Uses read-only Graph scopes
    - Verifies all 8 Service Principals exist
    - Checks device group configuration
    - Validates Windows Cloud Login service principal configuration
    - Confirms policy exists and is assigned
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # Mode: 'Setup' to run onboarding, 'Validate' to check existing setup
    [Parameter()][ValidateSet('Setup', 'Validate')][string]$Mode = 'Setup'
)

$DeviceGroupName = "Opal App Device Group"
$DeviceGroupRule = "Windows 365 Opal Device Pool"
$DeviceGroupDescription = "Device group for Opal Machines. This group has been configured by the Opal app. Any changes made to this group may cause the Opal app to not function as expected or break entirely."
$PolicyJsonURL ="https://res.cdn.office.net/s01-alps/prod/5mttl/devicePolicy.json"
$GraphScopes     = @(
    "Application.ReadWrite.All",
    "DeviceManagementConfiguration.ReadWrite.All",
    "Group.ReadWrite.All"
)

# App IDs for SP creation (idempotent ensure)
$AppIdsToEnsure = @(
    "03b184b5-8cb6-45d1-bef1-10db52790f06",  # Opal | Opal Primary App
    "90c719d1-2849-4e57-a1d1-0c9edb406be2",  # OpalNative | On Box Agent
    "0af06dc6-e4b5-4f28-818e-e78e62d137a5",  # CloudPC-MX | Windows 365
    "9cdead84-a844-4324-93f2-b2e6bb768d07",  # WVD | Azure Virtual Desktop
    "a85cf173-4192-42f8-81fa-777a763e6e2c",  # WindowsVirtualDesktopClient | Azure Virtual Desktop Client
    "50e95039-b200-4007-bc97-8d5790743a63",  # WVD-ARM | Azure Virtual Desktop ARM Provider
    "270efc09-cd0d-444b-a71f-39af4910ec45",  # WindowsCloudLogin | Windows Cloud Login
    "351add99-7ff7-4e1f-870f-f98b509209c2"   # CloudDevicePlatform | CloudDevicePlatform (Prod)
)

function Write-Info($msg) { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Write-ErrorDetails {
    <#
      Consolidated error message output with optional details
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    
    Write-Err $Message
    if ($ErrorRecord) {
        if ($ErrorRecord.Exception -and $ErrorRecord.Exception.Message) {
            Write-Err $ErrorRecord.Exception.Message
        }
        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            Write-Err ("Details: " + $ErrorRecord.ErrorDetails.Message)
        }
        # Also log the full error if there's additional context
        if ($ErrorRecord.FullyQualifiedErrorId) {
            Write-Host ("Error ID: {0}" -f $ErrorRecord.FullyQualifiedErrorId) -ForegroundColor DarkRed
        }
    } else {
        Write-Err "No error details available"
    }
}

function Invoke-WithErrorHandling {
    <#
      Wraps operation with standard error handling pattern
    #>
    param(
        [Parameter(Mandatory)][string]$OperationName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    
    try {
        & $ScriptBlock
    }
    catch {
        Write-Err "$OperationName failed."
        Write-Err $_.Exception.Message
        if ($_.ScriptStackTrace) { 
            Write-Warn ("Stack: " + $_.ScriptStackTrace) 
        }
        throw
    }
}

function Ensure-Module {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][string]$MinVersion = "2.0.0"
    )
    
    Write-Host ("  Checking module: {0}..." -f $Name) -ForegroundColor Gray -NoNewline
    
    # Check if already imported first
    if (Get-Module -Name $Name) {
        Write-Host " LOADED" -ForegroundColor Green
        return
    }
    
    # Try to import (will install if missing)
    try {
        Import-Module -Name $Name -MinimumVersion $MinVersion -ErrorAction Stop
        Write-Host " IMPORTED" -ForegroundColor Green
    }
    catch {
        # Module not found - install it
        Write-Host " NOT FOUND" -ForegroundColor Yellow
        Write-Info ("  Installing module {0} (this may take a moment)..." -f $Name)
        
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber
        Import-Module -Name $Name -MinimumVersion $MinVersion
        Write-Ok ("  Successfully installed {0}" -f $Name)
    }
}

function Initialize-GraphModules {
    <#
      Ensures all required Microsoft Graph modules are installed and loaded.
      Shows step-by-step progress.
    #>
    [CmdletBinding()]
    param()

    Write-Host "`n[INFO] Preparing Microsoft Graph modules..." -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Gray
    
    $modules = @(
        @{ Name = "Microsoft.Graph.Authentication"; Description = "Authentication Module" }
        @{ Name = "Microsoft.Graph.Beta.Applications"; Description = "Applications Module" }
        @{ Name = "Microsoft.Graph.Beta.DeviceManagement"; Description = "Device Management Module" }
        @{ Name = "Microsoft.Graph.Beta.Groups"; Description = "Groups Module" }
    )
    
    $stepNum = 1
    $totalSteps = $modules.Count
    
    foreach ($module in $modules) {
        Write-Host "`nStep $stepNum/$totalSteps`: $($module.Description)" -ForegroundColor Cyan
        Ensure-Module -Name $module.Name
        $stepNum++
    }
    
    Write-Host "`n========================================" -ForegroundColor Gray
    Write-Ok "All modules ready!`n"
}

function Get-GraphResultWithPagination {
    <#
      Helper function to fetch Graph API results with pagination support.
      Optionally stops early if a matching item is found.
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][scriptblock]$StopCondition
    )
    
    $result = Invoke-MgGraphRequest -Method GET -Uri $Uri
    $allItems = @()
    
    do {
        $allItems += $result.value
        
        # Check stop condition on each page
        if ($StopCondition) {
            $foundItem = $result.value | Where-Object $StopCondition | Select-Object -First 1
            if ($foundItem) {
                return $foundItem
            }
        }
        
        # Get next page if available
        if ($result.'@odata.nextLink') {
            $result = Invoke-MgGraphRequest -Method GET -Uri $result.'@odata.nextLink'
        }
    } while ($result.'@odata.nextLink')
    
    # Return first item if no stop condition, or all items if nothing found
    if ($allItems.Count -gt 0) {
        return $allItems[0]
    }
    return $null
}

function Connect-ToMicrosoftGraph {
    [CmdletBinding()]
    param(
        [Parameter()][string[]]$Scopes
    )
    # Disconnect any existing session to ensure clean authentication
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore errors if not connected
    }
    
    Write-Info "Connecting to Microsoft Graph..."
    Connect-MgGraph -Scopes $Scopes
    $ctx = Get-MgContext
    Write-Ok ("Connected. Tenant: {0}, App: {1}, Scopes: {2}" -f $ctx.TenantId, $ctx.ClientId, ($ctx.Scopes -join ", "))
    
    # Verify that all required scopes are present
    $missingScopes = @()
    foreach ($requiredScope in $Scopes) {
        if ($ctx.Scopes -notcontains $requiredScope) {
            $missingScopes += $requiredScope
        }
    }
    
    if ($missingScopes.Count -gt 0) {
        Write-Err ("Missing required scopes: {0}" -f ($missingScopes -join ", "))
        Write-Err "Please re-authenticate with the required permissions."
        throw "Insufficient permissions: Missing scopes: $($missingScopes -join ', ')"
    }
    
    Write-Ok "All required scopes verified."
}

function Ensure-ServicePrincipals {
    <#
      Idempotently ensure Service Principals exist for a set of appIds.
      Creates only those that do not already exist in the tenant.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)][string[]]$AppIds
    )

    Write-Info ("Ensuring Service Principals exist for {0} appId(s)..." -f $AppIds.Count)

    foreach ($appId in $AppIds) {
        try {
            # Check existing (always perform read operations, even in WhatIf)
            $existing = $null
            if (-not $WhatIfPreference) {
                try {
                    $existing = Get-MgBetaServicePrincipal -Filter "appId eq '$appId'" -ConsistencyLevel eventual -CountVariable _
                }
                catch {
                    Write-ErrorDetails -Message ("Failed to query existing SP for appId {0}" -f $appId) -ErrorRecord $_
                    throw
                }
            }
            
            if ($existing) {
                Write-Ok ("SP already exists for appId {0} (objectId: {1})" -f $appId, $existing.Id)
                continue
            }

            if ($PSCmdlet.ShouldProcess(("appId {0}" -f $appId), "Create Service Principal")) {
                try {
                    $sp = New-MgBetaServicePrincipal -BodyParameter @{ appId = $appId }
                    Write-Ok ("Created Service Principal for appId {0} (objectId: {1})" -f $appId, $sp.Id)
                }
                catch {
                    Write-ErrorDetails -Message ("Failed to create SP for appId {0}" -f $appId) -ErrorRecord $_
                    throw
                }
            }
        }
        catch {
            # Always log full error details for outer catch
            Write-ErrorDetails -Message ("Service Principal operation failed for appId {0}" -f $appId) -ErrorRecord $_
            throw
        }
    }
}

function Ensure-DynamicDeviceGroup {
    <#
      Idempotently create (or reuse) a dynamic device group that matches enrollmentProfileName == $DeviceGroupName
      Returns the MgGroup object.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()

    $membershipRule = "(device.enrollmentProfileName -eq `"$DeviceGroupRule`")"

    Write-Info ("Ensuring dynamic device group '{0}' exists..." -f $DeviceGroupName)
    try {
        # Check existing (always perform read operations, even in WhatIf)
        $existing = $null
        if (-not $WhatIfPreference) {
            $existing = Get-MgBetaGroup -Filter "displayName eq '$DeviceGroupName'" -ConsistencyLevel eventual -CountVariable _
        }
        
        if ($existing) {
            Write-Ok ("Group already exists: {0} (id: {1})" -f $DeviceGroupName, $existing.Id)
            return $existing
        }

        if ($PSCmdlet.ShouldProcess($DeviceGroupName, "Create Dynamic Device Group")) {
            $group = New-MgBetaGroup `
                -DisplayName $DeviceGroupName `
                -Description $DeviceGroupDescription `
                -MailEnabled:$false `
                -MailNickName ("grp_" + ([System.Guid]::NewGuid().ToString("N").Substring(0,8))) `
                -MembershipRule $membershipRule `
                -MembershipRuleProcessingState 'On' `
                -GroupTypes @("DynamicMembership") `
                -SecurityEnabled

            Write-Ok ("Created dynamic device group (id: {0})" -f $group.Id)
            return $group
        }
        
        # Return null in WhatIf mode if group doesn't exist
        return $null
    }
    catch {
        Write-ErrorDetails -Message ("Error while ensuring dynamic group '{0}'" -f $DeviceGroupName) -ErrorRecord $_
        throw
    }
}

function Configure-WindowsCloudLoginSP {
    <#
      Configures the Windows Cloud Login service principal for remote desktop access.
      - Gets the service principal ID for Windows Cloud Login (270efc09-cd0d-444b-a71f-39af4910ec45)
      - Enables remote desktop protocol if not already enabled
      - Adds the device group to target device groups
      Returns the service principal object if successful.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)][string]$DeviceGroupId,
        [Parameter(Mandatory)][string]$DeviceGroupName
    )

    $windowsCloudLoginAppId = "270efc09-cd0d-444b-a71f-39af4910ec45"
    
    Write-Info ("Configuring Windows Cloud Login service principal for device group '{0}'..." -f $DeviceGroupName)
    
    try {
        # Get the service principal ID for Windows Cloud Login
        Write-Info ("Getting service principal for Windows Cloud Login (AppId: {0})..." -f $windowsCloudLoginAppId)
        
        if (-not $WhatIfPreference) {
            $servicePrincipal = Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=AppId eq '$windowsCloudLoginAppId'"
            
            if (-not $servicePrincipal.value -or $servicePrincipal.value.Count -eq 0) {
                Write-Err ("Service principal for Windows Cloud Login not found. AppId: {0}" -f $windowsCloudLoginAppId)
                throw "Windows Cloud Login service principal not found"
            }
            
            $spId = $servicePrincipal.value[0].id
            Write-Ok ("Found Windows Cloud Login service principal (ID: {0})" -f $spId)
            
            # Get the remote desktop security configuration
            Write-Info "Getting remote desktop security configuration..."
            
            try {
                $rdpConfig = Invoke-MgGraphRequest -Method GET `
                    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/remoteDesktopSecurityConfiguration"
                
                Write-Info ("Current RDP enabled status: {0}" -f $rdpConfig.isRemoteDesktopProtocolEnabled)
                
                # Enable RDP if it's not already enabled
                if (-not $rdpConfig.isRemoteDesktopProtocolEnabled) {
                    if ($PSCmdlet.ShouldProcess("Windows Cloud Login SP", "Enable Remote Desktop Protocol")) {
                        Write-Info "Enabling remote desktop protocol..."
                        
                        $patchBody = @{
                            isRemoteDesktopProtocolEnabled = $true
                        } | ConvertTo-Json
                        
                        Invoke-MgGraphRequest -Method PATCH `
                            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/remoteDesktopSecurityConfiguration" `
                            -ContentType "application/json" `
                            -Body $patchBody
                        
                        Write-Ok "Remote desktop protocol enabled successfully"
                    }
                } else {
                    Write-Ok "Remote desktop protocol is already enabled"
                }
                
                # Add the device group to target device groups
                if ($PSCmdlet.ShouldProcess("Windows Cloud Login SP", "Add device group to Windows Cloud Login targetted device groups")) {
                    Write-Info ("Adding device group '{0}' to target device groups..." -f $DeviceGroupName)
                    
                    # Check if group is already added (optional - we could just add it idempotently)
                    try {
                        $existingGroups = Invoke-MgGraphRequest -Method GET `
                            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/remoteDesktopSecurityConfiguration/targetDeviceGroups"
                        
                        $alreadyExists = $false
                        if ($existingGroups.value) {
                            foreach ($group in $existingGroups.value) {
                                if ($group.id -eq $DeviceGroupId) {
                                    $alreadyExists = $true
                                    Write-Ok ("Device group '{0}' is already in target device groups" -f $DeviceGroupName)
                                    break
                                }
                            }
                        }
                        
                        if (-not $alreadyExists) {
                            $deviceGroupBody = @{
                                '@odata.type' = '#microsoft.graph.targetDeviceGroup'
                                id = $DeviceGroupId
                                displayName = $DeviceGroupName
                            } | ConvertTo-Json
                            
                            Invoke-MgGraphRequest -Method POST `
                                -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/remoteDesktopSecurityConfiguration/targetDeviceGroups" `
                                -ContentType "application/json" `
                                -Body $deviceGroupBody
                            
                            Write-Ok ("Successfully added device group '{0}' to Windows Cloud Login target device groups" -f $DeviceGroupName)
                        }
                    }
                    catch {
                        Write-ErrorDetails -Message "Failed to add device group to target device groups" -ErrorRecord $_
                        throw
                    }
                }
                
                return $servicePrincipal.value[0]
                
            }
            catch {
                Write-ErrorDetails -Message "Failed to configure remote desktop security configuration" -ErrorRecord $_
                throw
            }
        } else {
            Write-Host ("What if: Would configure Windows Cloud Login SP for device group '{0}'" -f $DeviceGroupName) -ForegroundColor Cyan
            return $null
        }
    }
    catch {
        Write-ErrorDetails -Message "Error configuring Windows Cloud Login service principal" -ErrorRecord $_
        throw
    }
}

function New-PolicyFromJson {
    <#
      Creates a device policy via raw REST using Invoke-MgGraphRequest.
      Expects the JSON to match the beta /deviceManagement/configurationPolicies schema exactly.
      Returns the created policy object (as PSCustomObject).
      If a policy with the same name already exists, returns the existing policy instead.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()

    Write-Info ("Downloading policy JSON from '{0}'..." -f $PolicyJsonURL)
    
    try {
        $jsonRaw = Invoke-RestMethod -Uri $PolicyJsonURL -Method Get -ErrorAction Stop
        # Convert to string if it's an object
        if ($jsonRaw -is [PSCustomObject] -or $jsonRaw -is [hashtable]) {
            $jsonRaw = $jsonRaw | ConvertTo-Json -Depth 100
        }
    }
    catch {
        Write-ErrorDetails -Message ("Failed to download policy JSON from URL: {0}" -f $PolicyJsonURL) -ErrorRecord $_
        throw
    }
    
    if (-not $jsonRaw -or -not $jsonRaw.ToString().Trim()) {
        throw ("Policy JSON downloaded from URL is empty: {0}" -f $PolicyJsonURL)
    }

    # Optional: lightweight validation just to help catch obvious shape issues early.
    try {
        $jsonObj = $jsonRaw | ConvertFrom-Json
        foreach ($required in @("name","description","platforms","technologies","settings")) {
            if (-not $jsonObj.PSObject.Properties.Name -contains $required) {
                Write-Warn ("JSON missing top-level '{0}'. Ensure it matches the Settings Catalog policy schema." -f $required)
            }
        }
    } catch {
        throw ("Invalid JSON: {0}" -f $_.Exception.Message)
    }

    # Check if a policy with this name already exists
    $policyName = $jsonObj.name
    Write-Info ("Checking if policy '{0}' already exists..." -f $policyName)
    
    # Check existing (skip Graph API calls in WhatIf mode)
    if (-not $WhatIfPreference) {
        try {
            $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq '$policyName'"
            $existing = Get-GraphResultWithPagination -Uri $uri -StopCondition { $_.name -eq $policyName }
            
            if ($existing) {
                Write-Ok ("Policy already exists: id: {0}, name: {1}" -f $existing.id, $existing.name)
                return $existing
            }
        }
        catch {
            Write-Warn ("Could not check for existing policy: {0}" -f $_.Exception.Message)
            # Continue to create if check fails
        }
    }

    if ($PSCmdlet.ShouldProcess(("Configuration Policy: {0}" -f $policyName), "Create via REST (Invoke-MgGraphRequest)")) {
        try {
            $resp = Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" `
                -ContentType "application/json" `
                -Body $jsonRaw

            if ($resp -and $resp.id) {
                Write-Ok ("Created device configuration policy, id: {0}, name: {1}" -f $resp.id, $resp.name)
            } else {
                Write-Warn "Policy created but response did not include an 'id'."
            }
            return $resp
        }
        catch {
            Write-ErrorDetails -Message "Create policy (REST) failed" -ErrorRecord $_
            throw
        }
    }
    
    # Return null in WhatIf mode
    return $null
}

function Assign-PolicyToGroup {
    <#
      Assigns a configuration policy to a group.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][string]$GroupId
    )

    $body = @{
        assignments = @(
            @{
                target = @{
                    '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                    groupId       = $GroupId
                }
            }
        )
    }

    if ($PSCmdlet.ShouldProcess(("Policy {0}" -f $PolicyId), ("Assign to group {0}" -f $GroupId))) {
        try {
            Invoke-MgGraphRequest -Method POST `
                -Uri ("https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/{0}/assign" -f $PolicyId) `
                -ContentType "application/json" `
                -Body ($body | ConvertTo-Json -Depth 10)

            Write-Ok "Policy assignment completed."
        }
        catch {
            Write-ErrorDetails -Message "Assignment failed" -ErrorRecord $_
            throw
        }
    }
}

function Write-ResourceSummary {
    <#
      Displays a consistent summary of Device Group, Policy, and Assignment
    #>
    param(
        [Parameter(Mandatory)][object]$DeviceGroup,
        [Parameter(Mandatory)][object]$Policy,
        [Parameter()][int]$ServicePrincipalCount = 0
    )

    Write-Host "`n1. Device Group:" -ForegroundColor Yellow
    Write-Host ("     Name: {0}" -f $DeviceGroup.DisplayName) -ForegroundColor White
    Write-Host ("     Group ID: {0}" -f $DeviceGroup.Id) -ForegroundColor Gray
    Write-Host ("     Description: {0}" -f $DeviceGroup.Description) -ForegroundColor Gray
    Write-Host ("     Group Types: {0}" -f ($DeviceGroup.GroupTypes -join ", ")) -ForegroundColor Gray
    Write-Host ("     Membership Rule: {0}" -f $DeviceGroup.MembershipRule) -ForegroundColor Gray
    Write-Host ("     Membership Processing State: {0}`n" -f $DeviceGroup.MembershipRuleProcessingState) -ForegroundColor Gray

    Write-Host "2. Configuration Policy:" -ForegroundColor Yellow
    Write-Host ("     Name: {0}" -f $Policy.name) -ForegroundColor White
    Write-Host ("     Policy ID: {0}" -f $Policy.id) -ForegroundColor Gray
    Write-Host ("     Description: {0}" -f $Policy.description) -ForegroundColor Gray
    Write-Host ("     Platforms: {0}" -f $Policy.platforms) -ForegroundColor Gray
    Write-Host ("     Technologies: {0}" -f $Policy.technologies) -ForegroundColor Gray
    Write-Host ("     Settings Count: {0}`n" -f $Policy.settingCount) -ForegroundColor Gray

    Write-Host "3. Policy Assignment:" -ForegroundColor Yellow
    Write-Host ("     Status: Assigned") -ForegroundColor White
    Write-Host ("     Policy '{0}' -> Group '{1}'`n" -f $Policy.name, $DeviceGroup.DisplayName) -ForegroundColor Gray

    if ($ServicePrincipalCount -gt 0) {
        Write-Host "4. Service Principals:" -ForegroundColor Yellow
        Write-Host ("     {0} Service Principals ensured`n" -f $ServicePrincipalCount) -ForegroundColor White
    }
}

function Validate-Setup {
    <#
      Validates that the onboarding setup has been completed correctly.
      Checks for Service Principals, Device Group, and Policy.
      Returns a summary report.
    #>
    [CmdletBinding()]
    param()

    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "  VALIDATION REPORT" -ForegroundColor Magenta
    Write-Host "========================================`n" -ForegroundColor Magenta

    $validationResults = @{
        ServicePrincipals = @()
        DeviceGroup = $null
        Policy = $null
        PolicyAssignment = $null
        WindowsCloudLogin = $null
        AllChecksPass = $true
    }

    # 1. Check Service Principals
    Write-Host "1. Checking Service Principals..." -ForegroundColor Cyan
    Write-Host ("   Expected {0} Service Principals`n" -f $AppIdsToEnsure.Count) -ForegroundColor Gray
    
    foreach ($appId in $AppIdsToEnsure) {
        try {
            $sp = Get-MgBetaServicePrincipal -Filter "appId eq '$appId'" -ConsistencyLevel eventual -CountVariable _
            if ($sp) {
                Write-Ok ("   [OK] SP exists for appId: {0}" -f $appId)
                Write-Host ("     Object ID: {0}" -f $sp.Id) -ForegroundColor Gray
                Write-Host ("     Display Name: {0}`n" -f $sp.DisplayName) -ForegroundColor Gray
                $validationResults.ServicePrincipals += @{
                    AppId = $appId
                    ObjectId = $sp.Id
                    DisplayName = $sp.DisplayName
                    Status = "Found"
                }
            } else {
                Write-Err ("   [X] SP NOT FOUND for appId: {0}`n" -f $appId)
                $validationResults.ServicePrincipals += @{
                    AppId = $appId
                    Status = "Missing"
                }
                $validationResults.AllChecksPass = $false
            }
        }
        catch {
            Write-ErrorDetails -Message ("Error checking SP for appId {0}" -f $appId) -ErrorRecord $_
            $validationResults.AllChecksPass = $false
        }
    }

    # 2. Check Device Group
    Write-Host "`n2. Checking Device Group..." -ForegroundColor Cyan
    Write-Host ("   Expected Group Name: {0}`n" -f $DeviceGroupName) -ForegroundColor Gray
    
    try {
        $group = Get-MgBetaGroup -Filter "displayName eq '$DeviceGroupName'" -ConsistencyLevel eventual -CountVariable _
        if ($group) {
            Write-Ok ("   [OK] Device Group exists: {0}" -f $DeviceGroupName)
            $validationResults.DeviceGroup = @{
                Id = $group.Id
                DisplayName = $group.DisplayName
                Description = $group.Description
                MembershipRule = $group.MembershipRule
                GroupTypes = $group.GroupTypes
                MembershipRuleProcessingState = $group.MembershipRuleProcessingState
                Status = "Found"
            }
        } else {
            Write-Err ("   [X] Device Group NOT FOUND: {0}`n" -f $DeviceGroupName)
            $validationResults.AllChecksPass = $false
        }
    }
    catch {
        Write-ErrorDetails -Message "Error checking device group" -ErrorRecord $_
        $validationResults.AllChecksPass = $false
    }

    # 3. Check Policy
    Write-Host "`n3. Checking Configuration Policy..." -ForegroundColor Cyan
    
    try {
        # Load policy name from URL
        Write-Host ("   Downloading policy definition from: {0}`n" -f $PolicyJsonURL) -ForegroundColor Gray
        
        try {
            $jsonRaw = Invoke-RestMethod -Uri $PolicyJsonURL -Method Get
            # Convert to string if it's an object
            if ($jsonRaw -is [PSCustomObject] -or $jsonRaw -is [hashtable]) {
                $jsonRaw = $jsonRaw | ConvertTo-Json -Depth 100
            }
            $jsonObj = $jsonRaw | ConvertFrom-Json
            $policyName = $jsonObj.name
            
            Write-Host ("   Expected Policy Name: {0}`n" -f $policyName) -ForegroundColor Gray
            
            $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq '$policyName'"
            $policy = Get-GraphResultWithPagination -Uri $uri -StopCondition { $_.name -eq $policyName }
            
            if ($policy) {
                Write-Ok ("   [OK] Configuration Policy exists: {0}" -f $policy.name)
                
                $validationResults.Policy = @{
                    id = $policy.id
                    name = $policy.name
                    description = $policy.description
                    platforms = $policy.platforms
                    technologies = $policy.technologies
                    settingCount = $policy.settingCount
                    Status = "Found"
                }

                # 4. Check Policy Assignment
                if ($group -and $policy) {
                    Write-Host "`n4. Checking Policy Assignment..." -ForegroundColor Cyan
                    
                    try {
                        $assignments = Invoke-MgGraphRequest -Method GET `
                            -Uri ("https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/{0}/assignments" -f $policy.id)
                        
                        $assignedToGroup = $false
                        if ($assignments.value) {
                            foreach ($assignment in $assignments.value) {
                                if ($assignment.target.groupId -eq $group.Id) {
                                    $assignedToGroup = $true
                                    Write-Ok ("   [OK] Policy is assigned to group: {0}" -f $DeviceGroupName)
                                    break
                                }
                            }
                        }
                        
                        if (-not $assignedToGroup) {
                            Write-Err ("   [X] Policy is NOT assigned to group: {0}`n" -f $DeviceGroupName)
                            $validationResults.AllChecksPass = $false
                        }
                        
                        $validationResults.PolicyAssignment = @{
                            IsAssigned = $assignedToGroup
                            Status = if ($assignedToGroup) { "Found" } else { "Missing" }
                        }
                    }
                    catch {
                        Write-ErrorDetails -Message "Error checking policy assignment" -ErrorRecord $_
                        $validationResults.AllChecksPass = $false
                    }
                }
            } else {
                Write-Err ("   [X] Configuration Policy NOT FOUND: {0}`n" -f $policyName)
                $validationResults.AllChecksPass = $false
            }
        }
        catch {
            Write-ErrorDetails -Message "Failed to download policy JSON from URL" -ErrorRecord $_
            $validationResults.AllChecksPass = $false
        }
    }
    catch {
        Write-ErrorDetails -Message "Error checking policy" -ErrorRecord $_
        $validationResults.AllChecksPass = $false
    }
    
    # 5. Check Windows Cloud Login Configuration
    Write-Host "`n5. Checking Windows Cloud Login Configuration..." -ForegroundColor Cyan
    
    $windowsCloudLoginAppId = "270efc09-cd0d-444b-a71f-39af4910ec45"
    $validationResults.WindowsCloudLogin = @{
        ServicePrincipal = $null
        RdpEnabled = $false
        DeviceGroupAssigned = $false
        Status = "NotConfigured"
    }
    
    try {
        # Get Windows Cloud Login service principal
        $windowsCloudLoginSP = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=AppId eq '$windowsCloudLoginAppId'"
        
        if ($windowsCloudLoginSP.value -and $windowsCloudLoginSP.value.Count -gt 0) {
            $spId = $windowsCloudLoginSP.value[0].id
            Write-Ok ("   [OK] Windows Cloud Login SP found (ID: {0})" -f $spId)
            
            $validationResults.WindowsCloudLogin.ServicePrincipal = @{
                Id = $spId
                DisplayName = $windowsCloudLoginSP.value[0].displayName
            }
            
            # Check RDP configuration
            try {
                $rdpConfig = Invoke-MgGraphRequest -Method GET `
                    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/remoteDesktopSecurityConfiguration"
                
                if ($rdpConfig.isRemoteDesktopProtocolEnabled) {
                    Write-Ok ("   [OK] Remote Desktop Protocol is enabled")
                    $validationResults.WindowsCloudLogin.RdpEnabled = $true
                } else {
                    Write-Err ("   [X] Remote Desktop Protocol is NOT enabled")
                    $validationResults.AllChecksPass = $false
                }
                
                # Check if device group is in target device groups
                if ($group) {
                    try {
                        $targetGroups = Invoke-MgGraphRequest -Method GET `
                            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/remoteDesktopSecurityConfiguration/targetDeviceGroups"
                        
                        $groupFound = $false
                        if ($targetGroups.value) {
                            foreach ($targetGroup in $targetGroups.value) {
                                if ($targetGroup.id -eq $group.Id) {
                                    $groupFound = $true
                                    Write-Ok ("   [OK] Device group '{0}' is assigned to Windows Cloud Login" -f $DeviceGroupName)
                                    break
                                }
                            }
                        }
                        
                        if ($groupFound) {
                            $validationResults.WindowsCloudLogin.DeviceGroupAssigned = $true
                            $validationResults.WindowsCloudLogin.Status = "Configured"
                        } else {
                            Write-Err ("   [X] Device group '{0}' is NOT assigned to Windows Cloud Login" -f $DeviceGroupName)
                            $validationResults.AllChecksPass = $false
                        }
                    }
                    catch {
                        Write-ErrorDetails -Message "Error checking target device groups" -ErrorRecord $_
                        $validationResults.AllChecksPass = $false
                    }
                } else {
                    Write-Warn ("   [SKIP] Cannot check device group assignment - device group not found")
                }
            }
            catch {
                Write-ErrorDetails -Message "Error checking RDP configuration" -ErrorRecord $_
                $validationResults.AllChecksPass = $false
            }
        } else {
            Write-Err ("   [X] Windows Cloud Login service principal NOT FOUND (AppId: {0})" -f $windowsCloudLoginAppId)
            $validationResults.AllChecksPass = $false
        }
    }
    catch {
        Write-ErrorDetails -Message "Error checking Windows Cloud Login" -ErrorRecord $_
        $validationResults.AllChecksPass = $false
    }

    # Display summary if all resources were found
    if ($validationResults.DeviceGroup -and $validationResults.Policy -and $validationResults.PolicyAssignment.IsAssigned) {
        Write-Host "`nResource Details:`n" -ForegroundColor Cyan
        Write-ResourceSummary -DeviceGroup $validationResults.DeviceGroup -Policy $validationResults.Policy -ServicePrincipalCount $AppIdsToEnsure.Count
    }

    # Summary
    Write-Host "`n========================================" -ForegroundColor Magenta
    if ($validationResults.AllChecksPass) {
        Write-Host "  [OK] ALL CHECKS PASSED" -ForegroundColor Green
    } else {
        Write-Host "  [X] SOME CHECKS FAILED" -ForegroundColor Red
    }
    Write-Host "========================================`n" -ForegroundColor Magenta

    return $validationResults
}

function Onboard {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()

    Invoke-WithErrorHandling -OperationName "Onboarding" -ScriptBlock {
        Initialize-GraphModules
        
        # Connect to Graph (skip in WhatIf mode)
        if (-not $WhatIfPreference) {
            Connect-ToMicrosoftGraph -Scopes $GraphScopes
        } else {
            Write-Host "What if: Connecting to Microsoft Graph with scopes: $($GraphScopes -join ', ')" -ForegroundColor Cyan
        }

        Ensure-ServicePrincipals -AppIds $AppIdsToEnsure -WhatIf:$WhatIfPreference -Confirm:$ConfirmPreference
        $deviceGroup = Ensure-DynamicDeviceGroup -WhatIf:$WhatIfPreference -Confirm:$ConfirmPreference
        
        # Configure Windows Cloud Login service principal after device group is created
        if ($deviceGroup) {
            Configure-WindowsCloudLoginSP -DeviceGroupId $deviceGroup.Id -DeviceGroupName $deviceGroup.DisplayName -WhatIf:$WhatIfPreference -Confirm:$ConfirmPreference
        }
        
        $policy = New-PolicyFromJson -WhatIf:$WhatIfPreference -Confirm:$ConfirmPreference
        
        if ($policy -and $deviceGroup) {
            Assign-PolicyToGroup -PolicyId $policy.Id -GroupId $deviceGroup.Id -WhatIf:$WhatIfPreference -Confirm:$ConfirmPreference
        }

        # Display summary of created resources (skip in WhatIf mode)
        if (-not $WhatIfPreference) {
            Write-Host "`n========================================" -ForegroundColor Green
            Write-Host "  SETUP COMPLETED SUCCESSFULLY" -ForegroundColor Green
            Write-Host "========================================`n" -ForegroundColor Green

            Write-Host "Created/Verified Resources:`n" -ForegroundColor Cyan
            
            if ($deviceGroup -and $policy) {
                Write-ResourceSummary -DeviceGroup $deviceGroup -Policy $policy -ServicePrincipalCount $AppIdsToEnsure.Count
            }

            Write-Host "========================================`n" -ForegroundColor Green
            Write-Ok "Onboarding flow completed."
        } else {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "  WHATIF: No changes were made" -ForegroundColor Cyan
            Write-Host "========================================`n" -ForegroundColor Cyan
        }
    }
}

function Run-Validation {
    [CmdletBinding()]
    param()

    Invoke-WithErrorHandling -OperationName "Validation" -ScriptBlock {
        Initialize-GraphModules
        
        # Use read-only scopes for validation (principle of least privilege)
        $readScopes = @(
            "Application.Read.All",
            "DeviceManagementConfiguration.Read.All",
            "Group.Read.All"
        )
        Connect-ToMicrosoftGraph -Scopes $readScopes

        $results = Validate-Setup
        
        if ($results.AllChecksPass) {
            Write-Ok "Validation completed successfully - all resources found."
            exit 0
        } else {
            Write-Warn "Validation completed with issues - some resources are missing."
            exit 1
        }
    }
}
function Write-ModeHeader {
    param([string]$ModeName)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  RUNNING $ModeName MODE" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

switch ($Mode) {
    'Setup' {
        Write-ModeHeader -ModeName "SETUP"
        Onboard
    }
    'Validate' {
        # Validate mode is read-only, WhatIf doesn't apply
        if ($WhatIfPreference) {
            Write-Warn "WhatIf parameter is not applicable in Validate mode (read-only operations only)."
            return
        }
        
        Write-ModeHeader -ModeName "VALIDATION"
        Run-Validation
    }
}

# SIG # Begin signature block
# MIIoLQYJKoZIhvcNAQcCoIIoHjCCKBoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAtUD/O36xSF9sF
# V0TD2JeRBoxqHnMKEq/1/v6bV1rjiqCCDXYwggX0MIID3KADAgECAhMzAAAEhV6Z
# 7A5ZL83XAAAAAASFMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjUwNjE5MTgyMTM3WhcNMjYwNjE3MTgyMTM3WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDASkh1cpvuUqfbqxele7LCSHEamVNBfFE4uY1FkGsAdUF/vnjpE1dnAD9vMOqy
# 5ZO49ILhP4jiP/P2Pn9ao+5TDtKmcQ+pZdzbG7t43yRXJC3nXvTGQroodPi9USQi
# 9rI+0gwuXRKBII7L+k3kMkKLmFrsWUjzgXVCLYa6ZH7BCALAcJWZTwWPoiT4HpqQ
# hJcYLB7pfetAVCeBEVZD8itKQ6QA5/LQR+9X6dlSj4Vxta4JnpxvgSrkjXCz+tlJ
# 67ABZ551lw23RWU1uyfgCfEFhBfiyPR2WSjskPl9ap6qrf8fNQ1sGYun2p4JdXxe
# UAKf1hVa/3TQXjvPTiRXCnJPAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUuCZyGiCuLYE0aU7j5TFqY05kko0w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwNTM1OTAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBACjmqAp2Ci4sTHZci+qk
# tEAKsFk5HNVGKyWR2rFGXsd7cggZ04H5U4SV0fAL6fOE9dLvt4I7HBHLhpGdE5Uj
# Ly4NxLTG2bDAkeAVmxmd2uKWVGKym1aarDxXfv3GCN4mRX+Pn4c+py3S/6Kkt5eS
# DAIIsrzKw3Kh2SW1hCwXX/k1v4b+NH1Fjl+i/xPJspXCFuZB4aC5FLT5fgbRKqns
# WeAdn8DsrYQhT3QXLt6Nv3/dMzv7G/Cdpbdcoul8FYl+t3dmXM+SIClC3l2ae0wO
# lNrQ42yQEycuPU5OoqLT85jsZ7+4CaScfFINlO7l7Y7r/xauqHbSPQ1r3oIC+e71
# 5s2G3ClZa3y99aYx2lnXYe1srcrIx8NAXTViiypXVn9ZGmEkfNcfDiqGQwkml5z9
# nm3pWiBZ69adaBBbAFEjyJG4y0a76bel/4sDCVvaZzLM3TFbxVO9BQrjZRtbJZbk
# C3XArpLqZSfx53SuYdddxPX8pvcqFuEu8wcUeD05t9xNbJ4TtdAECJlEi0vvBxlm
# M5tzFXy2qZeqPMXHSQYqPgZ9jvScZ6NwznFD0+33kbzyhOSz/WuGbAu4cHZG8gKn
# lQVT4uA2Diex9DMs2WHiokNknYlLoUeWXW1QrJLpqO82TLyKTbBM/oZHAdIc0kzo
# STro9b3+vjn2809D0+SOOCVZMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGg0wghoJAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAASFXpnsDlkvzdcAAAAABIUwDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIEXnrOa/CULU6N+EniH1fwHd
# WG6rcjEo/bGy07gIVJbzMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAhP/HEfUyluww9wKE79Gjv9s7uraJ8MzI1xwTAbNSelssF2PqUVyJ+NYg
# Lh3MyFlQUQg1e8kQh6iP1R/ZP7vHGYjC97mikoY/ZSShn2cqgaaozOWwTHK1asL1
# GwV/dTw5ibyJsDDEFXbr6dR/1flkv6ZjMrXS1AMGHB1cRtMDPyYMqTdh9xZUATlo
# 3T6JtsNmkeNrxa9+pfHqnoYBMQwYupkbS3fBRHzpegUmTrvQBVI2j6aOZeHL5fLj
# tOiBKhgzleu0ivprXscDCc2GxIKaVdWXErrSXzZ9CEe8icLx/9rGBYPP2MpVm11U
# RUh1grl6f/V6L+OlGaILn+7NpIp6b6GCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCC
# F38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsq
# hkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCC88HPU9EPkYRzQb59Tf+hTywGwCRvbBwBD+LXoYni1xgIGaSc6MWYQ
# GBMyMDI1MTIwMTIyMzUxMC45NjRaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1l
# cmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046N0YwMC0w
# NUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghHtMIIHIDCCBQigAwIBAgITMwAAAgbXvFE4mCPsLAABAAACBjANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQy
# NTBaFw0yNjA0MjIxOTQyNTBaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046N0YwMC0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDpRIWbIM3Rlr397cjHaYx85l7I+ZVWGMCBCM911BpU
# 6+IGWCqksqgqefZFEjKzNVDYC9YcgITAz276NGgvECm4ZfNv/FPwcaSDz7xbDbsO
# oxbwQoHUNRro+x5ubZhT6WJeU97F06+vDjAw/Yt1vWOgRTqmP/dNr9oqIbE5oCLY
# dH3wI/noYmsJVc7966n+B7UAGAWU2se3Lz+xdxnNsNX4CR6zIMVJTSezP/2STNcx
# JTu9k2sl7/vzOhxJhCQ38rdaEoqhGHrXrmVkEhSv+S00DMJc1OIXxqfbwPjMqEVp
# 7K3kmczCkbum1BOIJ2wuDAbKuJelpteNZj/S58NSQw6khfuJAluqHK3igkS/Oux4
# 9qTP+rU+PQeNuD+GtrCopFucRmanQvxISGNoxnBq3UeDTqphm6aI7GMHtFD6DOjJ
# lllH1gVWXPTyivf+4tN8TmO6yIgB4uP00bH9jn/dyyxSjxPQ2nGvZtgtqnvq3h3T
# RjRnkc+e1XB1uatDa1zUcS7r3iodTpyATe2hgkVX3m4DhRzI6A4SJ6fbJM9isLH8
# AGKcymisKzYupAeFSTJ10JEFa6MjHQYYohoCF77R0CCwMNjvE4XfLHu+qKPY8GQf
# sZdigQ9clUAiydFmVt61hytoxZP7LmXbzjD0VecyzZoL4Equ1XszBsulAr5Ld2Kw
# cwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFO0wsLKdDGpT97cx3Iymyo/SBm4SMB8G
# A1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCG
# Tmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4w
# XAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2Vy
# dHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
# A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQD
# AgeAMA0GCSqGSIb3DQEBCwUAA4ICAQB23GZOfe9ThTUvD29i4t6lDpxJhpVRMme+
# UbyZhBFCZhoGTtjDdphAArU2Q61WYg3YVcl2RdJm5PUbZ2bA77zk+qtLxC+3dNxV
# sTcdtxPDSSWgwBHxTj6pCmoDNXolAYsWpvHQFCHDqEfAiBxX1dmaXbiTP1d0Xffv
# gR6dshUcqaH/mFfjDZAxLU1s6HcVgCvBQJlJ7xEG5jFKdtqapKWcbUHwTVqXQGbI
# lHVClNJ3yqW6Z3UJH/CFcYiLV/e68urTmGtiZxGSYb4SBSPArTrTYeHOlQIj/7lo
# VWmfWX2y4AGV/D+MzyZMyvFw4VyL0Vgq96EzQKyteiVeBaVEjxQKo3AcPULRF4Uz
# z98P2tCM5XbFZ3Qoj9PLg3rgFXr0oJEhfh2tqUrhTJd13+i4/fek9zWicoshlwXg
# Fu002ZWBVzASEFuqED48qyulZ/2jGJBcta+Fdk2loP2K3oSj4PQQe1MzzVZO52AX
# O42MHlhm3SHo3/RhQ+I1A0Ny+9uAehkQH6LrxkrVNvZG4f0PAKMbqUcXG7xznKJ0
# x0HYr5ayWGbHKZRcObU+/34ZpL9NrXOedVDXmSd2ylKSl/vvi1QwNJqXJl/+gJkQ
# EetqmHAUFQkFtemi8MUXQG2w/RDHXXwWAjE+qIDZLQ/k4z2Z216tWaR6RDKHGkwe
# CoDtQtzkHTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZI
# hvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# MjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAy
# MDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25Phdg
# M/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPF
# dvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6
# GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBp
# Dco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50Zu
# yjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3E
# XzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0
# lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1q
# GFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ
# +QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PA
# PBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkw
# EgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxG
# NSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARV
# MFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAK
# BggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMC
# AYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvX
# zpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20v
# cGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYI
# KwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG
# 9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0x
# M7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmC
# VgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449
# xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wM
# nosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDS
# PeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2d
# Y3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxn
# GSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+Crvs
# QWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokL
# jzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL
# 6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNQ
# MIICOAIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEn
# MCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjdGMDAtMDVFMC1EOTQ3MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQAE
# a0f118XHM/VNdqKBs4QXxNnN96CBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7NhPwDAiGA8yMDI1MTIwMTE3MzI0
# OFoYDzIwMjUxMjAyMTczMjQ4WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDs2E/A
# AgEAMAoCAQACAhl+AgH/MAcCAQACAhLRMAoCBQDs2aFAAgEAMDYGCisGAQQBhFkK
# BAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJ
# KoZIhvcNAQELBQADggEBADw+AfBIikLGlm3wk/H/PFK+YcriMmvfTRBwz8qukwvj
# a+n1g4obgeJZuCLzCEV9J4n5ntGtyF+YHWakV9ItWsD5aaRCHii51GCMD0nTWQjL
# QEKzQeR0HzhhGX/mutmsyaJNhqeX68aFruiDXMldphgRk3fmOz+ye1swcCuNNo9H
# i8Jv74xA6dE3CZJV8ZJu6d5jYT2CaXvrDtFMdT4kHdNTMin+BMOIikvRpYj9wgJD
# SkNCwZt9GHI/BgczxM2cpcxKx4BPX9VN30NzkF/IeKYN1CC8RHP7KLQUr+1e2dgt
# 3P5rV7jRF6VlcffRQGtlCebM6LtUGYFb4IxJwkjPPIMxggQNMIIECQIBATCBkzB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAgbXvFE4mCPsLAABAAAC
# BjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEE
# MC8GCSqGSIb3DQEJBDEiBCATGdEu8eUjKvYdt3JJrvjjOJCpdFibV/MJJgbTmQQI
# xjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIODo9ZSIkZ6dVtKT+E/uZx2W
# Ay7KiXM5R1JIOhNJf0vSMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAAIG17xROJgj7CwAAQAAAgYwIgQg0mgUGplpPSOUIVtZcXce3Oj0
# q5xOuvZW+f9JZ1PtajAwDQYJKoZIhvcNAQELBQAEggIAoD65sP5piXILMe+kW/k3
# HbdraKrH36nHfQFzjcmCXk7vZohKR8w91yaM/xTEMKjetBpb0QTc3Smt4iyLJ/nP
# Vzr2wT+le8EL23h6aUhZZGhQ5tVLFYwzKr/nLlfuRhf561hSrj9oiWFKgLNYC4i6
# y1m5mxStDI4o47LH9id8OaTiOjuIs/EKqbtCGdSiMtP0Ls0RbSE1gfzeUOyqIMII
# hrebqYAow74qGvLIxgnwKT0PtkwyyOF3vKpfxKkvL6929mvPV1QbBYpc8e4ZbMI4
# hrNuNK3OKtl7Ip3OhcIXkP9EXULWfpYDA15L65u90TY4jxp7wTpj1qhxrUMHbeqG
# GdgJ7Ic+aAeblZ6mgfLFQRCxX1Gd7TYxwOhvw7KaUWUP1kzKwheD7cW+yqZiM94d
# UlknelzryDlTXBBz5adwK6ZX8NDs19st9pvPhf3l3069VZ/b2H1edASVFoSjd8v8
# M7kaOWjfoTt4T50bfXIolRB2cwHFgEHTp9VRM3VF3AiWhFt76vBzhCP+e08yHIqH
# AZTaPH6HsELKazaRn1Sqdzr+vZwu0Ezw+0zQhUBdsN+y/FZOjwKwGVY1FmrFgo8k
# vWskn+vpr0xB6y0iL1jdpBWFPjY7OdQJf4aVlhGAKyReNyFpQSz05nVH46irwEgL
# R0sz9bJ18VcmJv92DaxUWHA=
# SIG # End signature block
