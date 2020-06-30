<#
.SYNOPSIS
    A Description of what this script does
.PARAMETER ParameterName
    A description of the parameters, if the script accepts them
.PARAMETER ScriptSettingsFile
    Optional. If you want to run the script with an alternative settings.json file, specify the file's full path
.PARAMETER UnloadModulesOnExit
    Optional. Useful during development, if changes are made to the modules in between script executions. Unloads the modules so that the latest versions are loaded each time the script runs.
#>
Param(
    [Parameter(Mandatory = $False)][string]$ParameterName,
    [Parameter(Mandatory = $False)][string]$global:ScriptSettingsFile = ".\settings.json",
    [Parameter(Mandatory = $False)][switch]$global:UnloadModulesOnExit
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
    # Custom wrapper to connect to Azure AD using a service principal. Services are "Core","Graph",etc.
Connect-AzSp -Services "Core"

# / SCRIPT PREPARATION

# CUSTOM VARIABLES
# / CUSTOM VARIABLES

# CUSTOM FUNCTIONS
# / CUSTOM FUNCTIONS

# EXECUTE TASKS
For ($i=0; $i -lt 100; $i++) {
    "I'm doing something"
}
# / EXECUTE TASKS

# FINISH SCRIPT
Exit-Script