<#
.SYNOPSIS
    This script gathers the last 30 days of Secure Score reports and provides an analysis of trends
.PARAMETER ParameterName
    A description of the parameters, if the script accepts them
.PARAMETER ScriptSettingsFile
    Optional. If you want to run the script with an alternative settings.json file, specify the file's full path
#>
Param(
    [Parameter(Mandatory = $False)][string]$ParameterName,
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
    # Custom wrapper to connect to Azure AD using a service principal. Services are "Core","Graph",etc.
Connect-AzSp -Services "Graph"

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

[int32]$NumberOfReports = $SecureScores.Count/7
Write-Log "The script will process the last $NumberOfReports weeks of Secure Score reports."

# Pull the weekly reports
$Reports = @()
For ($i=0; $i -le $SecureScores.Count; $i+=7) {
	$Reports += $SecureScores[$i]
}

# Reverse the array to iterate through it from oldest to newest
[array]::Reverse($Reports)

# Prepare the array that will store the records for the CSV file
$Output = @()
[int]$noChange = 0

ForEach ( $report in $Reports ) {
    Write-Log "Generating report for $($report.CreatedDateTime)"

    $record = [ordered]@{
        "Date" = $report.CreatedDateTime;
		"Overall Score" = $report.CurrentScore;
		"Overall Score Change" = ( $previousReport ? $report.CurrentScore - $previousReport.CurrentScore : $noChange );
		"Highest Possible Score" = $report.MaxScore;
		"Highest Possible Score Change" = ( $previousReport ? $report.MaxScore - $previousReport.MaxScore : $noChange );
		"Score Percentage" = [int]($report.Currentscore/$report.MaxScore);
		"Score Percentage Change" = ( $previousReport ? [int]($report.Currentscore/$report.MaxScore) - [int]($previousReport.Currentscore/$previousReport.MaxScore) : $noChange );
	}

    ForEach ( $control in $report.ControlScores ) {
		$controlName = $control.ControlName
        $scoreProfile = $ScoreProfiles | Where { $_.Id -eq $controlName }
		@{
            "$ControlName Score" = $control.Score;
            "$ControlName Score Change" = ( $previousReport ? $control.Score - ($previousReport.ControlScores | Where {$_.ControlName -eq $control.ControlName}).Score : $noChange);
            "$ControlName Highest Possible Score" = $scoreProfile.MaxScore;
            "$ControlName Highest Possible Score Change" = $scoreProfile.MaxScore;
            "$ControlName Score Percentage" = [int]($control.Score / $scoreProfile.MaxScore);
            "$ControlName Score Percentage Change" = ( $previousReport ? [int]($control.Score / $scoreProfile.MaxScore) - [int]($($previousReport.ControlScores | Where {$_.ControlName -eq $control.ControlName}).Score  / $scoreProfile.MaxScore) : $noChange );
            "$ControlName Title" = $scoreProfile.Title;
		}.GetEnumerator() | ForEach {
			$record[$_.Key] = $_.Value
		}
	}

	$Output += ,[pscustomobject]$record
	
	# Stash a copy of the current report to compare it to the next one
	$previousReport = $report
}

If (-not (Test-Path ".\Reports")) {
	[void](New-Item -ItemType Directory -Name "Reports")
}

$reportFileName = ".\Reports\Secure Score Analysis - $($Reports[-1].CreatedDateTime.ToString("yyyy-MM-dd")).csv"
Write-Log "Saving report as '$reportFileName'"
$Output | Export-Csv $reportFileName -NoTypeInformation

# / EXECUTE TASKS

# FINISH SCRIPT
Exit-Script