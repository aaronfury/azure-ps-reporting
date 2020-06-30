<#
.SYNOPSIS
    Creates a new Azure Service Principal, and provides the manual steps that you must perform after creation to grant permissions for running reports.
.PARAMETER ScriptSettingsFile
    Optional. If you want to run the script with an alternative settings.json file, specify the file's full path
#>
Param(
    [Parameter(Mandatory = $False)][string]$global:ScriptSettingsFile = ".\settings.json"
    # Add any additional parameters here (make sure to add a comma to the previous line)
)

# DEFAULT SCRIPT HEADER
Try {
    Import-Module ".\AzPsr-Foundational.psm1" -ErrorAction Stop
} Catch {
    "ERROR: itopia Core PS Module not found. $_"
    Return
}
# / DEFAULT SCRIPT HEADER

# SCRIPT PREPARATION
    # Initialize the script and start logging
Invoke-ScriptInit -ScriptName $($MyInvocation.MyCommand.Name -replace '.ps1','') # We must pass the variable to the module functions because they cannot implicitly access variables in the script

Try {
    Connect-AzAccount -ErrorAction Stop
} Catch {
    Write-Log "Failed to authenticate to Azure. The specific error is: $_" -Level "ERROR" -Fatal
}

$notBefore = (Get-Date).AddMonths(-1) # Backdate the cert just to make sure there's no timing issues
$notAfter = (Get-Date).AddMonths(12) # Valid for 12 months
$cert = New-SelfSignedCertificate -Subject "CN=AzPsr" -CertStoreLocation "cert:\CurrentUser\My" -KeyExportPolicy NonExportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -NotAfter $notAfter -NotBefore $notBefore
$keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())

$sp = New-AzADServicePrincipal -DisplayName "Azure PS Reporting Scripts" -CertValue $keyValue -EndDate $cert.NotAfter -StartDate $cert.NotBefore

$AzSpThumb = $cert.Thumbprint
$AzAppId = $sp.ApplicationId
$AzTenantId = (Get-AzTenant).Id

New-AzRoleAssignment -RoleDefinitionName Reader -ServicePrincipalName $AzAppId

Write-Host "Service Principal created. Update the settings file with the following parameters to use this certificate for future script execution:"
Write-Host "AzTenantId : $AzTenantId"
Write-Host "AzAppId : $AzAppId"
Write-Host "AzSpThumb : $AzSpThumb"
Read-Host -Prompt "Press any key to continue"

Write-Host "You must also configure the Azure application to grant the following permissions:"
Write-Host "Azure Portal > Azure Active Directory > App registrations > Azure PS Reporting Scripts > API permissions"
Write-Host "Azure Graph API"
Write-Host "SecurityEvents : ReadWriteAll"
Write-Host "Organization: ReadAll"