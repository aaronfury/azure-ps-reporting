# Default values for emailing reports. These can be overridden by re-defining this hashtable in a specific script
$ReportEmailDefaults = @{
	"SmtpServer" = "smtprelay.sigconsult.com";
	"Recipients" = "admins@sigconsult.com";
	"CCRecipients" = "";
	"BCCRecipients" = "";
}

# Useful Functions

Function Connect-AzSp {
    If (-not $AzSpThumb -and -not $CreateAzSp) {
        Throw "This script requires an Azure AD Service Principal. To create one, use the -CreateAzSp parameter and then populate the $AzSpThumb variable with the provided value"
    }

    If ($CreateAzSp) {
        Connect-AzureAD

        $notAfter = (Get-Date).AddMonths(12) # Valid for 12 months
        $cert = New-SelfSignedCertificate -DnsName $tenantName -CertStoreLocation "cert:\LocalMachine\My" -KeyExportPolicy NonExportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -NotAfter $notAfter
        $thumb = $cert.Thumbprint
        $keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())

        $application = New-AzureADApplication -DisplayName "Acordis Consulting Reporting Scripts" -IdentifierUris "https://acordisconsulting.com"
        New-AzureADApplicationKeyCredential -ObjectId $application.ObjectId -CustomKeyIdentifier "acordis" -Type AsymmetricX509Cert -Usage Verify -Value $keyValue

        $sp = New-AzureADServicePrincipal -AppId $application.AppId

        Add-AzureADDirectoryRoleMember -ObjectId (Get-AzureADDirectoryRole -Filter 'DisplayName eq "Global Readers"').Objectid -RefObjectId $sp.ObjectId
        $AzTenantId = (Get-AzTenant).Id

        "Service Principal created. Update the script file with the following parameters:"
        "`$AzTenantId = $AzTenantId"
        "`$AzAppId = $($application.AppId)"
        "`$AzSpThumb = $thumb"
        Read-Host -Prompt "Press any key to exit."
        Exit
    }

    If ( $AzSpThumb -and $AzTenantId -and $AzAppId ) {
        Connect-AzAccount -CertificateThumbprint $AzSpThumb -ApplicationId $AzAppId -Tenant $AzTenantId -ServicePrincipal
    }
}

Function Start-Script {
	# Read in the Variables.json file
	If (Test-Path "variables.json" ) {
		$variablesData = Get-Content -Raw -Path "variables.json" | ConvertFrom-Json
	} Else {
		Throw "variables.json file not found. This file is required to connect to your Azure AD / Office 365 environment"
	}


    # Check for NuGet Package Provider
    If (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Write-Warning -Message "NuGet package provider not found. Installing..."
        Install-PackageProvider -Name NuGet -Force
    }

    # Check for and install PS modules
    'Az', 'AzureAD' | ForEach {
        If (-not (Get-Module -Name $_ -ListAvailable)) {
            Write-Warning -Message "PS Module '$_' not found. Installing..."
            Install-Module -Name $_ -AllowClobber -Force
        }
    }
}

Function Send-Email {
    Param(
        [string]$FromAddress,
        $Recipients,
        $CCRecipients,
        $BCCRecipients,
        [string]$Subject,
		[string]$Body,
		[string]$Styling,
		[string]$SmtpServer,
        $Attachments
    )

	Switch ( $False ) {
		($Subject) {
			Subject = "$ScriptName Email - $( Get-Date -Format "yyyy/MM/dd hh:mm:ss tt" )"
		}
		($Styling) {
			$Styling = @"
<style>
	table { width: 80%; margin: 1em auto; }
	th { text-align: left; background: #ddd; border-collapse: collapse; padding: 0.5em; }
	td { border-bottom: 1px solid #ddd; padding: 0.25em 0.5em; }
</style>
"@
		}
		($Body) {
			$Body = @"
<div style="font-family: Calibri, sans-serif !important; color: #606060 !important;">
    <h1>This is a blank message</h1>
</div>
"@
		}
		($SmtpServer) {
			$SmtpServer = $ReportEmailDefaults["SmtpServer"]
		}
		($CCRecipients) {
			$CCRecipients = $ReportEmailDefaults["CCRecipients"]
		}
		($BCCRecipients) {
			$BCCRecipients = $ReportEmailDefaults["BCCRecipients"]
		}
	}

    $MessageParams = @{
        From = $FromAddress;
        To = $Recipients;
        SmtpServer = $SmtpServer;
        #UseSSL = $True;
        Subject = $Subject;
        Body = $Body;
        BodyAsHtml = $True;
    }

    If ( $CCRecipients ) {
        If ( $CCRecipients -is [string] ) {
            $CCRecipients = $CCRecipients -split ";"
        }
        $MessageParams.Add( "Cc", $CCRecipients )
    }
    If ( $BCCRecipients ) {
        If ( $BCCRecipients -is [string] ) {
            $BCCRecipients = $BCCRecipients -split ";"
        }
        $MessageParams.Add( "Bcc", $BCCRecipients )
    }

    If ( $Attachments ) { $MessageParams.Add( "Attachments", $Attachments ) }

    Try {
        Write-Log "Emailing report to $( $Recipients -join "," )..."
        Send-MailMessage @MessageParams @credSplat
    } Catch {
        Write-Log "Could not send report email. Check the parameters for the next iteration of the script." -Level "ERROR"
        Write-Log "Line $( $_.InvocationInfo.ScriptLineNumber ) - $_" -Level "ERROR"
    }
}

Function Write-Data {
    [CmdletBinding()]Param(
        [Parameter(Mandatory=$True,Position=1,ValueFromPipeline=$true)]$Record,
        [Parameter(Mandatory=$False, Position=2)][ValidateSet("csv","text","json")]$WriteType = "csv",
        [Parameter(Mandatory=$False, Position=2)]$Output = $OutputFile,
        [Parameter(Mandatory=$False, Position=3)][bool]$Force = $False
    )

    If ( $Record -is [hashtable] ) {
        $Record = [PSCustomObject]$Record
    }

    If ( -not (Test-Path $Output) ) {
        Write-Log "Output file $Output did not exist. Creating..." -Level "VERBOSE"
        If ( $Output -like "*\*") {
            $ParentPath = Split-Path $Output
            If (-not (Test-Path "$ParentPath\") ) {
                Try {
                    New-Item -ItemType Directory -Path $ParentPath -Force | Out-Null
                } Catch {
                    Write-Log $_
                    Write-Log "Could not create parent path for output file" -Level "ERROR" -Fatal
                }
            }
        }
    }

    Switch ( $WriteType ) {
        "csv" {
            $Record | Export-Csv -Append -Path $Output -NoTypeInformation -Force -Encoding ASCII
        }
        "text" {
            $Record | Out-File -FilePath $Output -Append -Encoding ASCII
        }
        "json" {
            ConvertTo-Json $Record | Out-File -FilePath $Output -Append -Encoding utf8
        }
    }
}

Function Write-Log {
    Param(
        $Message,
		[string]$Level = "INFO",
		[switch]$Silent,
        [switch]$Fatal
    )

    If ( $Message -is [System.Management.Automation.ErrorRecord] -and $Level -eq "INFO" ) {
        $Level = "ERROR"
    }

    # Ignore VERBOSE entries If the "Verbose" flag is not set
    If ( $Level -eq "VERBOSE" -and $VerbosePreference -ne "Continue" ) { Return }

    # Set the color for the console output and update counters
    Switch ( $Level ) {
        "WARNING" { $Color = "Yellow"; $TotalWarnings++; Break }
        "ERROR" { $Color = "Red"; $TotalErrors++; Break }
        "VERBOSE" { $Color = "Gray"; Break }
        Default { $Color = "White" }
    }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    If ( $Message -is [System.Management.Automation.ErrorRecord] ) {
        $Output = "$Level`t: $Message at line $($Message.InvocationInfo.ScriptLineNumber)"
    } Else {
        $Output = "$Level`t: $Message"
    }

	If ( -not $Silent ) {
		Write-Host $Output -Fore $Color
	}

    "$Timestamp`t$Output" | Add-Content $LogFile

    If ( $Fatal ) {
        "FATAL: The previous error was fatal. The script will now exit." | Add-Content $LogFile
        Write-Host "FATAL: The previous error was fatal. The script will now poop the bed." -Fore Red
        Exit-Script
    }
}

Start-Script

# Connect to Azure AD
Connect-AzSp

$exchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://outlook.office365.com/powershell-liveid/" -Credential $o365Credential -Authentication "Basic" -AllowRedirection
Import-PSSession $exchangeSession -DisableNameChecking