#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Scans network for active systems and detects if they are physical or virtual
.DESCRIPTION
    Scans a network subnet for systems responding to protocols and determines if 
    each system is physical or virtual. Saves results to a CSV file.
.PARAMETER ConfigPath
    Path to the configuration JSON file
.PARAMETER OutputPath
    Path to save the CSV file of active systems
.PARAMETER TestICMP
    Test systems with ICMP ping (default: $true)
.PARAMETER TestSMB
    Test systems with SMB port 445 (default: $true)
.PARAMETER TestRDP
    Test systems with RDP port 3389 (default: $true)
.PARAMETER TestWinRM
    Test systems with WinRM port 5985 (default: $true)
.PARAMETER DetectHostType
    Detect if systems are physical or virtual (default: $true)
.EXAMPLE
    .\Scan-NetworkSystems.ps1
.NOTES
    Version: 2.1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "inventory-config.json",
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "active-systems.csv",
    
    [Parameter(Mandatory = $false)]
    [bool]$TestICMP = $true,
    
    [Parameter(Mandatory = $false)]
    [bool]$TestSMB = $true,
    
    [Parameter(Mandatory = $false)]
    [bool]$TestRDP = $true,
    
    [Parameter(Mandatory = $false)]
    [bool]$TestWinRM = $true,
    
    [Parameter(Mandatory = $false)]
    [bool]$DetectHostType = $true
)

# Create timestamp for logging
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = "NetworkScan-$timestamp.log"

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Debug')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Set color based on level
    switch ($Level) {
        'Info'    { $color = 'White' }
        'Warning' { $color = 'Yellow' }
        'Error'   { $color = 'Red' }
        'Success' { $color = 'Green' }
        'Debug'   { $color = 'Gray' }
        default   { $color = 'White' }
    }
    
    # Output to console (only show debug if requested)
    if ($Level -ne 'Debug' -or $VerbosePreference -eq 'Continue') {
        Write-Host $logMessage -ForegroundColor $color
    }
    
    # Always log to file
    Add-Content -Path $logFile -Value $logMessage
}
function Set-WinRMTrustedHosts {
    [CmdletBinding()]
    param(
        [switch]$AddAllHosts
    )

    try {
        # Check if running as Administrator
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Log "This function requires administrative privileges." -Level Error
            return $false
        }

        # Add all hosts to TrustedHosts
        if ($AddAllHosts) {
            Write-Log "Adding all hosts to WinRM TrustedHosts..." -Level Info
            Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
            Write-Log "Successfully added all hosts to TrustedHosts" -Level Success
        }

        return $true
    }
    catch {
        Write-Log "Error configuring WinRM TrustedHosts: $_" -Level Error
        return $false
    }
}
function Test-Port {
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [int]$Port,
        [int]$Timeout = 1000
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connection = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
        $success = $connection.AsyncWaitHandle.WaitOne($Timeout, $false)
        
        if ($success) {
            try {
                $tcpClient.EndConnect($connection)
                return $true
            } catch {
                return $false
            }
        } else {
            return $false
        }
    } catch {
        return $false
    } finally {
        if ($tcpClient -ne $null) {
            $tcpClient.Close()
        }
    }
}

function Detect-HostType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 10
    )

    $result = [PSCustomObject]@{
        ComputerName = $ComputerName
        IsVirtual = $false
        Error = $null
    }

    try {
        # Connect to the remote system using WinRM without creating session options
        $scriptBlock = {
            # Get system information
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
            
            # Get the model and manufacturer
            $model = $computerSystem.Model
            $manufacturer = $computerSystem.Manufacturer
            
            # Check if it's a virtual machine
            $isVirtual = $false
            $virtualKeywords = @(
                'virtual', 'vmware', 'vbox', 'hyperv', 'xen', 'kvm', 'bochs',
                'qemu', 'parallels', 'virtual machine', 'vm:'
            )
            
            foreach ($keyword in $virtualKeywords) {
                if ($model -match $keyword -or $manufacturer -match $keyword) {
                    $isVirtual = $true
                    break
                }
            }
            
            # Return the results
            return @{
                IsVirtual = $isVirtual
            }
        }
        
        # Use simple timeout parameter instead of session options
        $remoteResult = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock $scriptBlock -ErrorAction Stop
        
        # Update the result object
        $result.IsVirtual = $remoteResult.IsVirtual
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

function Initialize-ScanResults {
    # Create a file to store scan results
    $scanResultsFile = "scan-results-$timestamp.csv"
    Write-Log "Creating scan results file: $scanResultsFile" -Level Info
    
    # Create headers for the CSV file - including host type but not model/manufacturer
    "IPAddress,IsOnline,ICMPResponse,SMBResponse,RDPResponse,WinRMResponse,IsVirtual,Timestamp" | 
        Out-File -FilePath $scanResultsFile -Encoding utf8
    
    return $scanResultsFile
}

function Save-HostResult {
    param(
        [string]$ScanResultsFile,
        [string]$IPAddress,
        [bool]$IsOnline,
        [bool]$ICMPResponse,
        [bool]$SMBResponse,
        [bool]$RDPResponse,
        [bool]$WinRMResponse,
        [bool]$IsVirtual = $false
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Create the CSV line - with IsVirtual but without model/manufacturer
    $line = "$IPAddress,$IsOnline,$ICMPResponse,$SMBResponse,$RDPResponse,$WinRMResponse,$IsVirtual,$timestamp"
    
    # Append to the scan results file
    $line | Out-File -FilePath $ScanResultsFile -Encoding utf8 -Append
}

function Process-ScanResults {
    param(
        [string]$ScanResultsFile,
        [string]$OutputPath
    )
    
    # Import the scan results
    if (Test-Path $ScanResultsFile) {
        $scanResults = Import-Csv -Path $ScanResultsFile
        $activeHosts = $scanResults | Where-Object { $_.IsOnline -eq "True" }
        
        Write-Log "Imported $($scanResults.Count) scan results, found $($activeHosts.Count) active hosts" -Level Info
        
        # Export active hosts to output CSV
        if ($activeHosts.Count -gt 0) {
            $activeHosts | Export-Csv -Path $OutputPath -NoTypeInformation -Force
            Write-Log "Exported $($activeHosts.Count) active hosts to $OutputPath" -Level Success
            
            # Verify the file size
            $fileSize = (Get-Item -Path $OutputPath).Length
            Write-Log "Output file size: $fileSize bytes" -Level Debug
            
            if ($fileSize -lt 10) {
                Write-Log "Warning: Output file seems too small!" -Level Warning
            }
        } else {
            Write-Log "No active hosts found" -Level Warning
            # Create empty CSV with headers
            "IPAddress,IsOnline,ICMPResponse,SMBResponse,RDPResponse,WinRMResponse,IsVirtual,Timestamp" | 
                Out-File -FilePath $OutputPath -Encoding utf8
        }
    } else {
        Write-Log "Scan results file not found: $ScanResultsFile" -Level Error
    }
}

# Main execution
try {
    Write-Log "Starting network scan (Version 2.1)" -Level Info
    Write-Log "Protocol tests: ICMP=$TestICMP, SMB=$TestSMB, RDP=$TestRDP, WinRM=$TestWinRM, DetectHostType=$DetectHostType" -Level Info
    
    # Load configuration
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Log "Configuration file not found: $ConfigPath" -Level Error
        exit 1
    }
    
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    Set-WinRMTrustedHosts -AddAllHosts

    # Validate configuration
    if (-not $config.Subnet -or -not $config.Execution -or -not $config.Credentials) {
        Write-Log "Invalid configuration file: Missing required sections" -Level Error
        exit 1
    }
    
    # Create credential object for WinRM connections
    $securePassword = ConvertTo-SecureString -String $config.Credentials.Password -AsPlainText -Force
    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.Credentials.Username, $securePassword
    
    # Initialize scan results file
    $scanResultsFile = Initialize-ScanResults
    
    # Generate IP list
    $baseSubnet = $config.Subnet.BaseSubnet
    $startIP = $config.Subnet.StartIP
    $endIP = $config.Subnet.EndIP
    $timeoutSeconds = $config.Execution.ConnectionTimeoutSeconds
    
    $ipList = $startIP..$endIP | ForEach-Object { "$baseSubnet.$_" }
    $totalIPs = $ipList.Count
    
    Write-Log "Scanning $totalIPs IP addresses in subnet $baseSubnet ($startIP to $endIP)" -Level Info
    
    # Process each IP address
    $processed = 0
    $active = 0
    
    foreach ($ip in $ipList) {
        $processed++
        
        # Show progress
        if ($processed % 10 -eq 0 -or $processed -eq $totalIPs) {
            Write-Progress -Activity "Scanning IP addresses" -Status "$processed of $totalIPs ($active active)" -PercentComplete (($processed / $totalIPs) * 100)
            Write-Log "Progress: $processed of $totalIPs IP addresses scanned, $active active hosts found" -Level Debug
        }
        
        # Test ICMP
        $icmpResult = $false
        if ($TestICMP) {
            try {
                $icmpResult = Test-Connection -ComputerName $ip -Count 1 -Quiet -TimeoutSeconds $timeoutSeconds
            } catch {
                $icmpResult = $false
            }
        }
        
        # Test SMB (port 445)
        $smbResult = $false
        if ($TestSMB) {
            $smbResult = Test-Port -ComputerName $ip -Port 445 -Timeout ($timeoutSeconds * 1000)
        }
        
        # Test RDP (port 3389)
        $rdpResult = $false
        if ($TestRDP) {
            $rdpResult = Test-Port -ComputerName $ip -Port 3389 -Timeout ($timeoutSeconds * 1000)
        }
        
        # Test WinRM (port 5985)
        $winrmResult = $false
        if ($TestWinRM) {
            $winrmResult = Test-Port -ComputerName $ip -Port 5985 -Timeout ($timeoutSeconds * 1000)
        }
        
        # Determine if host is online (any test passed)
        $isOnline = $icmpResult -or $smbResult -or $rdpResult -or $winrmResult
        
        # Save result if online
        if ($isOnline) {
            $active++
            Write-Log "Host $ip is active (ICMP=$icmpResult, SMB=$smbResult, RDP=$rdpResult, WinRM=$winrmResult)" -Level Info
            
            # If WinRM is available and DetectHostType is enabled, detect if physical or virtual
            $isVirtual = $false
            
            if ($DetectHostType -and $winrmResult) {
                Write-Log "Detecting host type for $ip..." -Level Info
                $hostTypeResult = Detect-HostType -ComputerName $ip -Credential $credential -TimeoutSeconds $timeoutSeconds
                
                if ($hostTypeResult.Error -eq $null) {
                    $isVirtual = $hostTypeResult.IsVirtual
                    if ($isVirtual) {
                        Write-Log "Host $ip is virtual" -Level Info
                    } else {
                        Write-Log "Host $ip is physical" -Level Info
                    }
                } else {
                    Write-Log "Failed to detect host type for $ip : $($hostTypeResult.Error)" -Level Warning
                }
            }
            
            Save-HostResult -ScanResultsFile $scanResultsFile -IPAddress $ip -IsOnline $isOnline `
                           -ICMPResponse $icmpResult -SMBResponse $smbResult -RDPResponse $rdpResult -WinRMResponse $winrmResult `
                           -IsVirtual $isVirtual
        }
    }
    
    Write-Progress -Activity "Scanning IP addresses" -Completed
    
    # Process scan results
    Write-Log "Scan complete. Found $active active hosts out of $totalIPs total IPs scanned." -Level Success
    Process-ScanResults -ScanResultsFile $scanResultsFile -OutputPath $OutputPath
    
    Write-Log "Network scan completed successfully" -Level Success
    exit 0
}
catch {
    Write-Log "Error in network scan: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}