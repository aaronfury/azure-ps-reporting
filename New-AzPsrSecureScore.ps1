<#
.SYNOPSIS
    Retreives Azure Secure Score reports and compiles a report
.PARAMETER Days
    Integer. The number of previous reports to get. Reports are generated daily by Azure. A value of '0' will retreive all reports. Default is '0'.
.PARAMETER ScriptSettingsFile
    Optional. If you want to run the script with an alternative settings.json file, specify the file's full path
#>
Param(
    [Parameter(Mandatory = $False)][int32]$NumberOfReports = 0,
    [Parameter(Mandatory = $False)][int32]$OutputFormat = "JSON",
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
    # Custom wrapper to connect to Azure AD using a service principal
Connect-AzSp -Service "Graph"

# / SCRIPT PREPARATION

# CUSTOM VARIABLES
# / CUSTOM VARIABLES

# CUSTOM FUNCTIONS
# / CUSTOM FUNCTIONS

# EXECUTE TASKS
Write-Log "Retrieving Secure Score reports..."
$SecureScores = Get-MgSecuritySecureScore
Write-Log "Retrieved $($SecureScores.Count) reports"

Write-Log "Retrieving Secure Score profiles..."
$ScoreProfiles = Get-MgSecuritySecureScoreControlProfile

If ( $NumberOfReports ) {
    Write-Log "The script will only process the most recent $NumberOfReports reports"
    $SecureScores = $SecureScores[0..($NumberOfReports - 1)]
}

ForEach ( $report in $SecureScores ) {
    Write-Log "Generating report for $($report.CreatedDateTime)"

    $data = [ordered]@{
        "Date" = $report.CreatedDateTime;
        "OverallScore" = $report.CurrentScore;
        "HighestPossibleScore" = $report.MaxScore;
    }

    ForEach ( $control in $report.ControlScores ) {
        $scoreProfile = $ScoreProfiles | Where { $_.Id -eq $control.ControlName }
        $data[$control.ControlName] = @{
            "Score" = $control.Score;
            "MaxScore" = $scoreProfile.MaxScore;
            "Title" = $scoreProfile.Title;
            "ProfileType" = $scoreProfile.ActionType;
            "Description" = $control.Description
        }
    }

    If (-not (Test-Path ".\Reports")) {
        [void](New-Item -ItemType Directory -Name "Reports")
    }
    $reportFileName = ".\Reports\Secure Score Report - $($report.CreatedDateTime.ToString("yyyy-MM-dd")).json"
    Write-Log "Saving report as '$reportFileName'"
    $data | ConvertTo-Json | Out-File $reportFileName
}

# / EXECUTE TASKS

# FINISH SCRIPT
Exit-Script