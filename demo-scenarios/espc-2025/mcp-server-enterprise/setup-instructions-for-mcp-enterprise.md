# Setup Instructions for Microsoft Enterprise MCP

These instructions are based on the source guide, different users can have different experiences on different devices and previous installations of Graph PowerShell. I elected to keep my existing Graph PS modules. This guide was written December 3rd, 2025, expect changes later as this is a preview MCP.

Source: https://github.com/mcp/microsoft/EnterpriseMCP

## PowerShell instructions

Install Entra PowerShell Beta:

```azurepowershell
Install-Module Microsoft.Entra.Beta -Force -AllowClobber

```

Connect to Tenant (recommended test/demo tenant):

```azurepowershell
Connect-Entra -Scopes 'Application.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All'
```

Register the MCP Server for Enterprise in your tenant and grant all permissions to Visual Studio Code:

```azurepowershell
Grant-EntraBetaMCPServerPermission -ApplicationName VisualStudioCode
```

Output should be something like:

Operating on MCP client: Visual Studio Code
Granting all available scopes: MCP.AccessReview.Read.All, MCP.AdministrativeUnit.Read.All, MCP.Application.Read.All, MCP.AuditLog.Read.All, MCP.AuthenticationContext.Read.All, MCP.Device.Read.All, MCP.DirectoryRecommendations.Read.All, MCP.Domain.Read.All, MCP.EntitlementManagement.Read.All, MCP.GroupMember.Read.All, MCP.HealthMonitoringAlert.Read.All, MCP.IdentityRiskEvent.Read.All, MCP.IdentityRiskyServicePrincipal.Read.All, MCP.IdentityRiskyUser.Read.All, MCP.LicenseAssignment.Read.All, MCP.LifecycleWorkflows-CustomExt.Read.All, MCP.LifecycleWorkflows-Reports.Read.All, MCP.LifecycleWorkflows-Workflow.Read.All, MCP.LifecycleWorkflows-Workflow.ReadBasic.All, MCP.LifecycleWorkflows.Read.All, MCP.NetworkAccess-Reports.Read.All, MCP.NetworkAccess.Read.All, MCP.Organization.Read.All, MCP.Policy.Read.All, MCP.Policy.Read.ConditionalAccess, MCP.ProvisioningLog.Read.All, MCP.Reports.Read.All, MCP.RoleAssignmentSchedule.Read.Directory, MCP.RoleEligibilitySchedule.Read.Directory, MCP.RoleManagement.Read.Directory, MCP.Synchronization.Read.All, MCP.User.Read.All, MCP.UserAuthenticationMethod.Read.All

✓ Successfully granted permissions to Visual Studio Code

Id                                          ClientId                             ConsentType   ExpiryTime
--                                          --------                             -----------   ----------     
eVQ<your-id....> <your-guid> AllPrincipals 03.12.2026 17… 
