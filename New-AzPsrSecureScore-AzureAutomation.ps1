<#
This script is a modified version of 'New-AzPsrSecureScore' and is intended to run on Azure Automation.
This version is meant to run every day and keep a "running log" of the results, and to copy the results to weekly and monthly logs
You will need to create a RunAs credential for the Automation account, and assign it the necessary GRAPH
permissions.
#>

$storageAccountName = "POPULATE ME!"
$storageContainerName = "POPULATE ME!"
$storageResourceGroup = "POPULATE ME!"
$connectionName = "AzureRunAsConnection"

$ReportFileNames = @{}
"Running","Daily","Monthly" | ForEach-Object { 
	$ReportFileNames[$_] = "SecureScoreAnalysis - $_.csv"
}

Function Get-ReportOnStorage {
	Param(
		[string]$ReportType
	)

	Try {
		Get-AzureStorageBlobContent -Container $storageContainerName -Blob $ReportFileNames[$ReportType] -ErrorAction Stop -Force
		$Report = Import-Csv $ReportFileNames[$ReportType] -ErrorAction Stop
		Remove-Item $ReportFileNames[$ReportType] -Force
	} Catch {
		Write-Host "Failed to retrieve the $ReportType report. The report may not exist. The specific error is: $_"
		$Report = @()
	}

	Return $Report
}

Function Set-ReportOnStorage {
	Param(
		$Report,
		[string]$ReportType
	)

	$Report | Export-Csv $ReportFileNames[$ReportType] -NoTypeInformation
	Try {
		# Copy the running report to the storage account
		Set-AzureStorageBlobContent -File $ReportFileNames[$ReportType] -Container $storageContainerName -BlobType "Block" -Force
	} Catch {
		"Failed to save the $ReportType report to Azure Storage. The specific error is: $_"
	}
}

Try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Connect-Graph `
        -TenantId $servicePrincipalConnection.TenantId `
        -ClientId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
} Catch {
    "Failed to connect to the GRAPH API using the Azure Automation RunAs account. The specific error is: $_"
    Exit
}

Try {
    "Retrieving Secure Score reports..."
    $SecureScores = Get-MgSecuritySecureScore -ErrorAction Stop
    "Retrieved $($SecureScores.Count) reports"
} Catch {
    "Failed to retrieve Secure Score reports. The specific error is: $_"
    Exit
}
Try {
    "Retrieving Secure Score profiles..."
    $ScoreProfiles = Get-MgSecuritySecureScoreControlProfile
} Catch {
    "Failed to retrieve Secure Score profiles. The specific error is: $_"
    Exit
}

# Pull the most recent two reports
$PreviousReport = $SecureScores[1]
$CurrentReport = $SecureScores[0]

# Shorthand for unchanged values
[int]$noChange = 0

"Processing report for $($CurrentReport.CreatedDateTime.ToShortDateString())"

$record = [ordered]@{
	"Date" = $CurrentReport.CreatedDateTime.ToShortDateString();
	"Overall Score" = $CurrentReport.CurrentScore;
	"Overall Score Change" = $( if ( $PreviousReport ) { $CurrentReport.CurrentScore - $PreviousReport.CurrentScore } else { $noChange } );
	"Highest Possible Score" = $CurrentReport.MaxScore;
	"Highest Possible Score Change" = $( if ( $PreviousReport ) { $CurrentReport.MaxScore - $PreviousReport.MaxScore } else { $noChange } );
	"Score Percentage" = [int]($CurrentReport.Currentscore/$CurrentReport.MaxScore);
	"Score Percentage Change" = $( if ( $PreviousReport ) { [int]($CurrentReport.Currentscore/$CurrentReport.MaxScore) - [int]($PreviousReport.Currentscore/$PreviousReport.MaxScore) } else { $noChange } );
}

ForEach ( $control in $CurrentReport.ControlScores ) {
	$controlName = $control.ControlName
	$scoreProfile = $ScoreProfiles | Where-Object { $_.Id -eq $controlName }
	@{
		"$ControlName Score" = $control.Score;
		"$ControlName Score Change" = $( if ( $PreviousReport ) { $control.Score - ($PreviousReport.ControlScores | Where-Object {$_.ControlName -eq $control.ControlName}).Score } else { $noChange } );
		"$ControlName Highest Possible Score" = $scoreProfile.MaxScore;
		"$ControlName Highest Possible Score Change" = $scoreProfile.MaxScore;
		"$ControlName Score Percentage" = [int]($control.Score / $scoreProfile.MaxScore);
		"$ControlName Score Percentage Change" = $( if ( $PreviousReport ) { [int]($control.Score / $scoreProfile.MaxScore) - [int]($($PreviousReport.ControlScores | Where-Object {$_.ControlName -eq $control.ControlName}).Score  / $scoreProfile.MaxScore) } else { $noChange } );
		"$ControlName Title" = $scoreProfile.Title;
	}.GetEnumerator() | ForEach-Object {
		$record[$_.Key] = $_.Value
	}
}

$record = [pscustomobject]$record

Try {
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
} Catch {
    "Failed to connect to Azure RM using the RunAs Service Account. The specific error is: $_"
    Exit
}
Try {
    Set-AzureRmCurrentStorageAccount -StorageAccountName $storageAccountName -ResourceGroupName $storageResourceGroup
} Catch {
    "Failed to set the Current Storage Account. The specific error is: $_"
    Exit
}

# Get and update the existing running report file
$RunningReport = Get-ReportOnStorage -ReportType "Running"
$RunningReport.Count
$RunningReport
$RunningReport += $record
Set-ReportOnStorage -Report $RunningReport -ReportType "Running"

$DailyReport = Get-ReportOnStorage -ReportType "Daily"
$DailyReport.Count
$DailyReport
If ( (Get-Date).Day -eq 1 ) { # First day of month, aggregate data and update monthly report
	$MonthlyReport = Get-ReportOnStorage -ReportType "Monthly"
	$MonthSummary = @{
		"Month" = ([datetime]::Parse($DailyReport[-1].Date)).ToString("MMMM yyyy")
		"Starting Score" = $DailyReport[0]."Overall Score"
		"Starting Score (Percentage of Max)" = $DailyReport[0]."Score Percentage"
		"Ending Score" = $DailyReport[-1]."Overall Score"
		"Ending Score (Percentage of Max)" = $DailyReport[-1]."Score Percentage"
		"Score Change" = $DailyReport[-1]."Overall Score" - $DailyReport[0]."Overall Score"
		"Score Change (Percentage)" = $DailyReport[-1]."Score Percentage" - $DailyReport[0]."Score Percentage"
		"Month Averaged Score" = ($DailyReport."Overall Score" | Measure-Object -Average).Average
		"Month-over-Month Change" = $DailyReport[-1]."Overall Score" - $MonthlyReport[-1]."Overall Score"
		"Month-over-Month Change (Percentage)" = $DailyReport[-1]."Score Percentage" - $MonthlyReport[-1]."Score Percentage"
	}
	$MonthlyReport += $MonthSummary
	Set-ReportOnStorage -ReportType "Monthly" -Report $MonthlyReport

	# Replace the daily report file with a new report that only contains the most recent record
	Set-ReportOnStorage -ReportType "Daily" -Report $record
} Else {
	$DailyReport += $record
	Set-ReportOnStorage -ReportType "Daily" -Report $DailyReport
}