# Requires -Version 8

Function Connect-AzSp {
    Param(
        [string[]]$Services
    )
    $AzSpThumb = $ScriptSettings.AzureConnection.AzSpThumb
    $AzAppId = $ScriptSettings.AzureConnection.AzAppId
    $AzTenantId = $ScriptSettings.AzureConnection.AzTenantId

    If ( $AzSpThumb -and $AzTenantId -and $AzAppId ) {
        Try {
            [void](Connect-AzAccount -CertificateThumbprint $AzSpThumb -ApplicationId $AzAppId -Tenant $AzTenantId -ServicePrincipal -ErrorAction Stop)
        } Catch {
            Write-Log "Failed to connect to Azure AD using the Service Principal info provided. Check your settings file and try again. The specific error is: $_" -Level "ERROR" -Fatal
        }

        Try {
            $cert = Get-Item Cert:\CurrentUser\My\$AzSpThumb -ErrorAction Stop
            [void](Connect-Graph -CertificateName $cert.Subject -ClientId $AzAppId -TenantId $AzTenantId -ErrorAction Stop)
        } Catch {
            Write-Log "Failed to connect to Microsoft Graph using the Service Principal info provided. Check your settings file and try again. The specific error is: $_" -Level "ERROR" -Fatal
        }
    } Else {
        Write-Log "The Azure PS Reporting scripts require a certificate-based Azure AD Service Principal to connect to your tenant. Use the 'New-AzPsrServicePrincipal.ps1' script to generate a new service principal. If you already have a service principal, configure the settings file (AzureConnection object) with the connectivity info for your tenant." -Level "ERROR" -Fatal
    }
}

Function Exit-Script {
    Write-Log "Exiting script...`r`n"
    If ( $Global:UnloadModulesOnExit) {
        If ( Get-Module "AzPsr-Foundational") {
            Write-Log "Unloading the AzPsr-Foundational module"
            [void](Disconnect-Graph -ErrorAction SilentlyContinue)
            [void](Disconnect-AzAccount -ErrorAction SilentlyContinue)
            Remove-Module AzPsr-Foundational -Force -ErrorAction SilentlyContinue
        }
    }
    Exit
}

Function Get-Confirmation {
	Param(
		[string]$Message,
		[switch]$ExitOnNo,
		[switch]$DefaultToYes,
		[string]$CustomOptions
	)

	If ( $CustomOptions ) {
		If ( $CustomOptions -cmatch "[A-Z]") {
			$DefaultOption = $Matches[0]
		}
		$Options = $CustomOptions -split ","

		$confirmation = Read-Host "$Message`n[$( $Options -join "/")]"

		If ( $DefaultOption -and ($confirmation -eq "") ) {
			Return $DefaultOption
		}

		While ( $Options -notcontains $confirmation ) {
			$confirmation = Read-Host "Invalid option. `n$Message`n[$( $Options -join " / ")]"
		}
		Return $confirmation
	} Else {
		If ( $DefaultToYes ) { $YesVar = "Y" } Else { $YesVar = "y" }

		Do {
			$confirmation = Read-Host "$Message [$YesVar/n]"

			Switch ( $confirmation ) {
				"n" {
					If ( $ExitOnNo ) {
						Write-Log "User declined confirmation." -Level "ERROR" -Fatal
					} Else {
						Return $False
					}
					Break
				}
				"y" {
					Return $True
				}
				default {
					If ( $DefaultToYes -and ($confirmation -eq "") ) { Return $True }
				}
			}
		} While ( -not $validInput )
	}
}

Function Invoke-ScriptInit {
    Param(
        [string]$ScriptName = "Azure PS Reporting"
    )

    # Read in the Settings.json file
    If (-not $global:SettingsFilePath) {
        $global:SettingsFilePath = ".\Settings.json"
    }

	If (Test-Path $global:SettingsFilePath ) {
		$global:ScriptSettings = Get-Content -Raw -Path $global:SettingsFilePath | ConvertFrom-Json
	} Else {
		Throw "$($global:SettingsFilePath).json file not found. This file is required to connect to your Azure AD / Office 365 environment"
    }
    
    # Initialize the log
    $script:LogFile = ( $global:ScriptSettings.ScriptConfig.Logfile -ne 'default' ) ? $global:ScriptSettings.ScriptConfig.Logfile : ".\$ScriptName - $(Get-Date -Format "yyyy-MM-dd hh-mm-tt").log"

    Write-Host "Loaded module $($MyInvocation.ScriptName -replace '.psm1','')"
    Write-Host "Using log file $LogFile..."

    If ( -not (Test-Path $LogFile ) ) {
        Try {
            Write-Host "Creating log file..."
            New-Item -Path $LogFile -ItemType file | Out-Null
        } Catch {
            Write-Host "Failed to create the log file. The specific error is:"
            $_
            Read-Host "Press a key to exit"
            Exit
        }
    }

    Write-Log "Initializing $ScriptName..."

    # Get current user. You know, for accountability
    $Executor = [Environment]::UserName
    Write-Log "Welcome, $Executor. Your actions are being logged. You know, for accountability."
    Start-Sleep -Seconds 1

    # Check for NuGet Package Provider
    If (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        If ( $global:ScriptSettings.ScriptConfig.AutoInstallTrustedModules ) {
            If ( ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) ) {
                Write-Log -Message "NuGet package provider not found. Installing..." -Level "WARNING"
                PowerShell -Command {Install-PackageProvider -Name NuGet -Force}
            } Else {
                Write-Log -Message "Installing the PS Package Provider NuGet requires running the script in elevated (administrator) mode. Restart the script in admin mode, or install the module manually by starting *Windows PowerShell* as an admin and running: 'Install-PackageProvider -Name NuGet -Force'" -Level "ERROR" -Fatal
            }
        } Else {
            Write-Log "NuGet package provider not found. To install it automatically, change 'AutoInstallTrustedModules' to 'true' in the settings file and re-run the script in an elevated (administrator) session." -Level "ERROR" -Fatal
        }
    }
    'Az', 'Microsoft.Graph' | ForEach {
        If ( -not (Get-Module -Name $_ -ListAvailable)) {
            If ( $global:ScriptSettings.ScriptConfig.AutoInstallTrustedModules ) {
                Write-Log "Module $_ not found. Installing..."
                Install-Module $_ -Force
            } Else {
                Write-Log "The script is not permitted to install modules. Change the 'AutoInstallTrustedModules' to 'true' in the settings file, or manually install the PS Module $_."
            }
        }

        Try {
            Write-Log "Importing PS module $_..."
            Import-Module $_
        } Catch {
            Write-Log "Failed to import PS module. The specific error is: $_" -Level "ERROR" -Fatal
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

    If ( $global:ScriptSettings.ReportEmail.DisableEmail ) {
        Write-Log "Report emails are disabled in the loaded settings file $($global:SettingsFilePath). Skipping this step..."
        Return
    }

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

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    If ( $Message -is [System.Management.Automation.ErrorRecord] ) {
        $Output = "$Level`t: $Message at line $($Message.InvocationInfo.ScriptLineNumber)"
    } Else {
        $Output = "$Level`t: $Message"
    }

	If ( -not $Silent ) {
        # Set the color for the console output and update counters
        Switch ( $Level ) {
            "WARNING" { $Color = "Yellow"; $TotalWarnings++; Break }
            "ERROR" { $Color = "Red"; $TotalErrors++; Break }
            "VERBOSE" { $Color = "Gray"; Break }
            Default { $Color = "White" }
        }

		Write-Host $Output -Fore $Color
	}

    "$Timestamp`t$Output" | Add-Content $LogFile

    If ( $Fatal ) {
        "FATAL: The previous error was fatal. The script will now exit." | Add-Content $LogFile
        Write-Host "FATAL: The previous error was fatal. The script will now exit." -Fore Red
        Exit-Script
    }
}