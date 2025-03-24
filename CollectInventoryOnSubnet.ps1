#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Collects system inventory information from multiple remote systems
.DESCRIPTION
    This script coordinates the collection of system inventory information by:
    1. Scanning the subnet for active systems
    2. Connecting to each using PowerShell Remoting
    3. Running the SystemInventory module on each system
    4. Collecting all JSON files in a central directory
.PARAMETER ConfigPath
    Path to the configuration JSON file (default: inventory-config.json)
.PARAMETER TargetIPs
    Optional list of specific IP addresses to target instead of scanning
.EXAMPLE
    .\Invoke-RemoteInventoryCollection.ps1
.EXAMPLE
    .\Invoke-RemoteInventoryCollection.ps1 -ConfigPath "custom-config.json"
.EXAMPLE
    .\Invoke-RemoteInventoryCollection.ps1 -TargetIPs "192.168.1.100","192.168.1.101"
.NOTES
    Author: System Administrator
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "inventory-config.json",
    
    [Parameter(Mandatory = $false)]
    [string[]]$TargetIPs
)

#region Functions

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',
        
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Set color based on level
    switch ($Level) {
        'Info'    { $color = 'White' }
        'Warning' { $color = 'Yellow' }
        'Error'   { $color = 'Red' }
        'Success' { $color = 'Green' }
        default   { $color = 'White' }
    }
    
    # Output to console
    Write-Host $logMessage -ForegroundColor $color
    
    # Output to log file if provided
    if ($LogFilePath) {
        Add-Content -Path $LogFilePath -Value $logMessage
    }
}

function Test-IPAddresses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseSubnet,
        
        [Parameter(Mandatory = $true)]
        [int]$StartIP,
        
        [Parameter(Mandatory = $true)]
        [int]$EndIP,
        
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,
        
        [Parameter(Mandatory = $true)]
        [int]$MaxConcurrent,
        
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath
    )
    
    Write-LogMessage -Message "Starting IP scan of subnet $BaseSubnet ($StartIP to $EndIP)" -Level Info -LogFilePath $LogFilePath
    
    # Generate IP list
    $ipList = $StartIP..$EndIP | ForEach-Object { "$BaseSubnet.$_" }
    $totalIPs = $ipList.Count
    
    Write-LogMessage -Message "Testing connectivity to $totalIPs IP addresses" -Level Info -LogFilePath $LogFilePath
    
    # Set up throttling
    $throttleLimit = $MaxConcurrent
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $throttleLimit, $sessionState, $Host)
    $pool.Open()
    
    $scriptBlock = {
        param($ip, $timeout)
        Write-Verbose "Testing IP address $ip"
        $result = Test-Connection -ComputerName $ip -Count 1 -Quiet -TimeoutSeconds $timeout
        Write-Host "Tested $ip : $result"  # Add this line for debugging
        [PSCustomObject]@{
            IPAddress = $ip
            IsOnline = $result
        }
    }
    
    # Create runspaces
    $runspaces = @()
    $results = [System.Collections.ArrayList]::new()
    
    foreach ($ip in $ipList) {
        $powerShell = [PowerShell]::Create().AddScript($scriptBlock).AddArgument($ip).AddArgument($TimeoutSeconds)
        $powerShell.RunspacePool = $pool
        
        $runspaces += [PSCustomObject]@{
            PowerShell = $powerShell
            Runspace = $powerShell.BeginInvoke()
            IPAddress = $ip
        }
        $runspaces[-1] | Add-Member -MemberType NoteProperty -Name ProcessingComplete -Value $false
    }
    
    # Process results as they complete
    $processed = 0
    $activeHosts = 0
    
    while ($runspaces.Where({ $_.Runspace.IsCompleted -eq $false }).Count -gt 0 -or $processed -lt $totalIPs) {
        foreach ($runspace in $runspaces.Where({ $_.Runspace.IsCompleted -eq $true -and $_.ProcessingComplete -ne $true })) {
            $result = $runspace.PowerShell.EndInvoke($runspace.Runspace)
            
            if ($result.IsOnline) {
                $activeHosts++
                $null = $results.Add($result)
                Write-LogMessage -Message "Host $($result.IPAddress) is active" -Level Info -LogFilePath $LogFilePath
            }
            
            $runspace.PowerShell.Dispose()
            $runspace.ProcessingComplete = $true
            $processed++
            
            # Show progress
            if ($processed % 25 -eq 0 -or $processed -eq $totalIPs) {
                $percentComplete = [math]::Round(($processed / $totalIPs) * 100)
                Write-Progress -Activity "Scanning IP addresses" -Status "$processed of $totalIPs complete ($activeHosts active)" -PercentComplete $percentComplete
            }
        }
        
        if ($runspaces.Where({ $_.Runspace.IsCompleted -eq $false }).Count -gt 0) {
            Start-Sleep -Milliseconds 100
        }
    }
    
    Write-Progress -Activity "Scanning IP addresses" -Completed
    
    # Clean up
    $pool.Close()
    $pool.Dispose()
    
    Write-LogMessage -Message "IP scan complete. Found $activeHosts active hosts." -Level Success -LogFilePath $LogFilePath
    
    return $results.Where({ $_.IsOnline -eq $true }).IPAddress
}

function Copy-ModuleToRemoteSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession]$Session,
        
        [Parameter(Mandatory = $true)]
        [string]$LocalModulePath,
        
        [Parameter(Mandatory = $true)]
        [string]$RemoteModulePath,
        
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath
    )
    
    try {
        # Create the remote directory if it doesn't exist
        Invoke-Command -Session $Session -ScriptBlock {
            param($path)
            if (!(Test-Path -Path $path)) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
            }
        } -ArgumentList $RemoteModulePath
        
        # Copy the module files
        Copy-Item -Path "$LocalModulePath\*" -Destination $RemoteModulePath -ToSession $Session -Recurse -Force
        
        # Create subnet.txt in the functions directory with subnet from config
        $remoteSubnetPath = Join-Path $RemoteModulePath "Functions\subnet.txt"
        $subnetContent = $config.Subnet.BaseSubnet
        Invoke-Command -Session $Session -ScriptBlock {
            param($path, $content)
            Set-Content -Path $path -Value $content -Force
        } -ArgumentList $remoteSubnetPath, $subnetContent
        
        Write-LogMessage -Message "Successfully copied module to $($Session.ComputerName)" -Level Success -LogFilePath $LogFilePath
        return $true
    }
    catch {
        Write-LogMessage -Message "Failed to copy module to $($Session.ComputerName): $_" -Level Error -LogFilePath $LogFilePath
        return $false
    }
}

function Invoke-RemoteInventoryCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession]$Session,
        
        [Parameter(Mandatory = $true)]
        [string]$RemoteModulePath,
        
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 10
    )
    
    try {
        $result = Invoke-Command -Session $Session -ScriptBlock {
            param($modulePath, $timeout)
            
            # Set execution policy for current process
            Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
            
            # Import the module
            Import-Module $modulePath -Force -DisableNameChecking
            
            # Run the inventory collection with timeout
            $scriptBlock = {
                # Export the inventory data
                $outputFile = Export-SystemInventory -OutputPath "$env:TEMP"
                
                # Return the output file path if successful
                if ($outputFile) {
                    return @{
                        Success = $true
                        FilePath = $outputFile
                        ErrorMessage = $null
                    }
                }
                else {
                    return @{
                        Success = $false
                        FilePath = $null
                        ErrorMessage = "Export-SystemInventory returned null"
                    }
                }
            }
            
            # Run the script block with timeout
            $job = Start-Job -ScriptBlock $scriptBlock
            
            if (Wait-Job -Job $job -Timeout ($timeout * 60)) {
                $result = Receive-Job -Job $job
                Remove-Job -Job $job
                return $result
            }
            else {
                Stop-Job -Job $job
                Remove-Job -Job $job
                return @{
                    Success = $false
                    FilePath = $null
                    ErrorMessage = "Operation timed out after $timeout minutes"
                }
            }
        } -ArgumentList $RemoteModulePath, $TimeoutMinutes
        
        if ($result.Success) {
            Write-LogMessage -Message "Successfully ran inventory collection on $($Session.ComputerName)" -Level Success -LogFilePath $LogFilePath
        }
        else {
            Write-LogMessage -Message "Failed to run inventory collection on $($Session.ComputerName): $($result.ErrorMessage)" -Level Error -LogFilePath $LogFilePath
        }
        
        return $result
    }
    catch {
        Write-LogMessage -Message "Error executing remote inventory collection on $($Session.ComputerName): $_" -Level Error -LogFilePath $LogFilePath
        return @{
            Success = $false
            FilePath = $null
            ErrorMessage = $_.ToString()
        }
    }
}

function Copy-InventoryFileFromRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession]$Session,
        
        [Parameter(Mandatory = $true)]
        [string]$RemoteFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$LocalOutputPath,
        
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath
    )
    
    try {
        # Get just the filename
        $fileName = Split-Path -Path $RemoteFilePath -Leaf
        $localFilePath = Join-Path -Path $LocalOutputPath -ChildPath $fileName
        
        # Copy the file
        Copy-Item -Path $RemoteFilePath -Destination $localFilePath -FromSession $Session -Force
        
        # Verify the file exists locally
        if (Test-Path -Path $localFilePath) {
            Write-LogMessage -Message "Successfully copied inventory file from $($Session.ComputerName) to $localFilePath" -Level Success -LogFilePath $LogFilePath
            return @{
                Success = $true
                LocalPath = $localFilePath
                ErrorMessage = $null
            }
        }
        else {
            Write-LogMessage -Message "Failed to copy inventory file from $($Session.ComputerName): File not found after copy" -Level Error -LogFilePath $LogFilePath
            return @{
                Success = $false
                LocalPath = $null
                ErrorMessage = "File not found after copy operation"
            }
        }
    }
    catch {
        Write-LogMessage -Message "Error copying inventory file from $($Session.ComputerName): $_" -Level Error -LogFilePath $LogFilePath
        return @{
            Success = $false
            LocalPath = $null
            ErrorMessage = $_.ToString()
        }
    }
}

function Cleanup-RemoteSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession]$Session,
        
        [Parameter(Mandatory = $true)]
        [string]$RemoteModulePath,
        
        [Parameter(Mandatory = $true)]
        [string]$RemoteFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath
    )
    
    try {
        # Remove the module directory and JSON file if they exist
        Invoke-Command -Session $Session -ScriptBlock {
            param($modulePath, $filePath)
            
            # Remove the module directory
            if (Test-Path -Path $modulePath) {
                Remove-Item -Path $modulePath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Remove the JSON file
            if (Test-Path -Path $filePath) {
                Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
            }
        } -ArgumentList $RemoteModulePath, $RemoteFilePath
        
        Write-LogMessage -Message "Successfully cleaned up temporary files on $($Session.ComputerName)" -Level Info -LogFilePath $LogFilePath
        return $true
    }
    catch {
        Write-LogMessage -Message "Failed to clean up temporary files on $($Session.ComputerName): $_" -Level Warning -LogFilePath $LogFilePath
        return $false
    }
}

function Validate-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath
    )
    
    try {
        # Simple validation - make sure it's a valid JSON file
        $json = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
        
        # Check for required properties
        if ($json.system -and $json.schema_metadata) {
            Write-LogMessage -Message "JSON validation passed for $FilePath" -Level Success -LogFilePath $LogFilePath
            return $true
        }
        else {
            Write-LogMessage -Message "JSON validation failed for $FilePath : Missing required properties" -Level Warning -LogFilePath $LogFilePath
            return $false
        }
    }
    catch {
        Write-LogMessage -Message "JSON validation failed for $FilePath : $_" -Level Warning -LogFilePath $LogFilePath
        return $false
    }
}

#endregion Functions

#region Main Script

# Ensure we have the required modules
if (-not (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.Management')) {
    Write-LogMessage -Message "Required module 'Microsoft.PowerShell.Management' not found" -Level Error
    exit 1
}

# Load configuration
try {
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-LogMessage -Message "Configuration file not found: $ConfigPath" -Level Error
        exit 1
    }
    
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    
    # Validate configuration
    if (-not $config.Credentials -or -not $config.Subnet -or -not $config.OutputSettings -or -not $config.ModuleSettings) {
        Write-LogMessage -Message "Invalid configuration file: Missing required sections" -Level Error
        exit 1
    }
}
catch {
    Write-LogMessage -Message "Failed to load configuration: $_" -Level Error
    exit 1
}

# Set up output directory
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$baseOutputDir = $config.OutputSettings.OutputDirectory

if ($config.OutputSettings.CreateTimestampedFolder) {
    $outputDir = Join-Path -Path $baseOutputDir -ChildPath "InventoryCollection-$timestamp"
}
else {
    $outputDir = $baseOutputDir
}

# Create output directory if it doesn't exist
if (-not (Test-Path -Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

# Set up log file
$logFile = Join-Path -Path $outputDir -ChildPath "InventoryCollection-$timestamp.log"
New-Item -Path $logFile -ItemType File -Force | Out-Null

Write-LogMessage -Message "Starting Remote Inventory Collection" -Level Info -LogFilePath $logFile
Write-LogMessage -Message "Output directory: $outputDir" -Level Info -LogFilePath $logFile
Write-LogMessage -Message "Log file: $logFile" -Level Info -LogFilePath $logFile

# Get list of active IP addresses
if ($TargetIPs) {
    $activeIPs = $TargetIPs
    Write-LogMessage -Message "Using provided list of $($activeIPs.Count) IP addresses" -Level Info -LogFilePath $logFile
}
else {
    $activeIPs = Test-IPAddresses -BaseSubnet $config.Subnet.BaseSubnet `
        -StartIP $config.Subnet.StartIP `
        -EndIP $config.Subnet.EndIP `
        -TimeoutSeconds $config.Execution.ConnectionTimeoutSeconds `
        -MaxConcurrent $config.Execution.MaxConcurrentJobs `
        -LogFilePath $logFile `
        -Verbose:$VerbosePreference
}

if ($activeIPs.Count -eq 0) {
    Write-LogMessage -Message "No active IP addresses found. Exiting." -Level Warning -LogFilePath $logFile
    exit 0
}

Write-LogMessage -Message "Found $($activeIPs.Count) active systems to process" -Level Info -LogFilePath $logFile

# Create credential object
$securePassword = ConvertTo-SecureString -String $config.Credentials.Password -AsPlainText -Force
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.Credentials.Username, $securePassword

# Process each active IP
$results = @{
    Success = 0
    Failed = 0
    Skipped = 0
    Details = @()
}

foreach ($ip in $activeIPs) {
    $currentSystem = @{
        IPAddress = $ip
        Status = "Processing"
        ErrorMessage = $null
        InventoryFile = $null
    }
    
    Write-LogMessage -Message "Processing system $ip" -Level Info -LogFilePath $logFile
    
    # Attempt to create PS Session
    $session = $null
    $retry = 0
    $maxRetries = $config.Execution.RetryCount
    
    while ($retry -le $maxRetries -and -not $session) {
        try {
            $session = New-PSSession -ComputerName $ip -Credential $credentials -ErrorAction Stop
            Write-LogMessage -Message "Successfully established PSSession with $ip" -Level Success -LogFilePath $logFile
        }
        catch {
            $retry++
            if ($retry -le $maxRetries) {
                Write-LogMessage -Message "Retry $retry/$maxRetries : Failed to connect to $ip - $_" -Level Warning -LogFilePath $logFile
                Start-Sleep -Seconds 5
            }
            else {
                Write-LogMessage -Message "Failed to connect to $ip after $maxRetries retries: $_" -Level Error -LogFilePath $logFile
                $currentSystem.Status = "Failed"
                $currentSystem.ErrorMessage = "Connection error: $_"
                $results.Failed++
                $results.Details += $currentSystem
                continue
            }
        }
    }
    
    if (-not $session) {
        continue
    }
    
    # Copy module to remote system
    $moduleCopied = Copy-ModuleToRemoteSystem -Session $session -LocalModulePath $config.ModuleSettings.ModulePath -RemoteModulePath $config.ModuleSettings.TempRemotePath -LogFilePath $logFile
    
    if (-not $moduleCopied) {
        $currentSystem.Status = "Failed"
        $currentSystem.ErrorMessage = "Failed to copy module"
        $results.Failed++
        $results.Details += $currentSystem
        Remove-PSSession -Session $session
        continue
    }
    
    # Run inventory collection
    $inventoryResult = Invoke-RemoteInventoryCollection -Session $session -RemoteModulePath $config.ModuleSettings.TempRemotePath -LogFilePath $logFile -TimeoutMinutes $config.Execution.ExecutionTimeoutMinutes
    
    if (-not $inventoryResult.Success) {
        $currentSystem.Status = "Failed"
        $currentSystem.ErrorMessage = "Inventory collection failed: $($inventoryResult.ErrorMessage)"
        $results.Failed++
        $results.Details += $currentSystem
        
        # Clean up and close session
        Cleanup-RemoteSystem -Session $session -RemoteModulePath $config.ModuleSettings.TempRemotePath -RemoteFilePath $null -LogFilePath $logFile
        Remove-PSSession -Session $session
        continue
    }
    
    # Copy inventory file to local system
    $copyResult = Copy-InventoryFileFromRemote -Session $session -RemoteFilePath $inventoryResult.FilePath -LocalOutputPath $outputDir -LogFilePath $logFile
    
    if (-not $copyResult.Success) {
        $currentSystem.Status = "Failed"
        $currentSystem.ErrorMessage = "Failed to copy inventory file: $($copyResult.ErrorMessage)"
        $results.Failed++
        $results.Details += $currentSystem
        
        # Clean up and close session
        Cleanup-RemoteSystem -Session $session -RemoteModulePath $config.ModuleSettings.TempRemotePath -RemoteFilePath $inventoryResult.FilePath -LogFilePath $logFile
        Remove-PSSession -Session $session
        continue
    }
    
    # Clean up and close session
    Cleanup-RemoteSystem -Session $session -RemoteModulePath $config.ModuleSettings.TempRemotePath -RemoteFilePath $inventoryResult.FilePath -LogFilePath $logFile
    Remove-PSSession -Session $session
    
    # Validate JSON file if required
    $validJson = $true
    if ($config.OutputSettings.ValidateJsonFiles) {
        $validJson = Validate-JsonFile -FilePath $copyResult.LocalPath -LogFilePath $logFile
    }
    
    if ($validJson) {
        $currentSystem.Status = "Success"
        $currentSystem.InventoryFile = $copyResult.LocalPath
        $results.Success++
    }
    else {
        $currentSystem.Status = "Warning"
        $currentSystem.InventoryFile = $copyResult.LocalPath
        $currentSystem.ErrorMessage = "JSON validation failed"
        $results.Success++  # Still count as success since we got the file
    }
    
    $results.Details += $currentSystem
}

# Output summary
Write-LogMessage -Message "Inventory Collection Summary:" -Level Info -LogFilePath $logFile
Write-LogMessage -Message "Total systems processed: $($activeIPs.Count)" -Level Info -LogFilePath $logFile
Write-LogMessage -Message "Successful: $($results.Success)" -Level Info -LogFilePath $logFile
Write-LogMessage -Message "Failed: $($results.Failed)" -Level Info -LogFilePath $logFile
Write-LogMessage -Message "Collection completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info -LogFilePath $logFile

# Export results to JSON
$resultsFile = Join-Path -Path $outputDir -ChildPath "CollectionResults-$timestamp.json"
$results | ConvertTo-Json -Depth 3 | Out-File -FilePath $resultsFile

Write-LogMessage -Message "Collection results saved to $resultsFile" -Level Success -LogFilePath $logFile
Write-LogMessage -Message "Remote Inventory Collection completed" -Level Success -LogFilePath $logFile

#endregion Main Script
