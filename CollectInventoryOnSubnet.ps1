#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Collects system inventory from physical (non-virtual) systems
.DESCRIPTION
    Processes a CSV file from Scan-NetworkSystems.ps1, filters for physical systems only,
    copies the SystemInventory module to each physical system, executes inventory collection,
    and copies the result files back to the host.
.PARAMETER CsvPath
    Path to the CSV file generated by Scan-NetworkSystems.ps1
.PARAMETER ConfigPath
    Path to the configuration JSON file (default: inventory-config.json)
.PARAMETER OutputPath
    Path to save the collected inventory files (default: PhysicalInventory-[timestamp])
.EXAMPLE
    .\Invoke-PhysicalSystemInventory.ps1 -CsvPath "active-systems.csv"
.EXAMPLE
    .\Invoke-PhysicalSystemInventory.ps1 -CsvPath "active-systems.csv" -ConfigPath "custom-config.json" -OutputPath "C:\Inventory"
.NOTES
    Author: System Administrator
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "inventory-config.json",
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ""
)

# Create timestamp for logging
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

# Set up output directory
if (-not $OutputPath) {
    $OutputPath = "PhysicalInventory"
}

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Set up log file
$logFile = Join-Path -Path $OutputPath -ChildPath "PhysicalInventory.log"
New-Item -Path $logFile -ItemType File -Force | Out-Null

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Debug')]
        [string]$Level = 'Info',
        
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = $logFile
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
    
    # Output to console (only show debug if verbose)
    if ($Level -ne 'Debug' -or $VerbosePreference -eq 'Continue') {
        Write-Host $logMessage -ForegroundColor $color
    }
    
    # Always log to file
    if ($LogFilePath) {
        Add-Content -Path $LogFilePath -Value $logMessage
    }
}

function Set-WinRMTrustedHosts {
    [CmdletBinding()]
    param()
    
    try {
        Write-LogMessage -Message "Adding all hosts to WinRM TrustedHosts..." -Level Info
        Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
        Write-LogMessage -Message "Successfully added all hosts to WinRM TrustedHosts" -Level Success
        return $true
    }
    catch {
        Write-LogMessage -Message "Error configuring WinRM TrustedHosts: $_" -Level Error
        return $false
    }
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
        [string]$SubnetValue
    )
    
    try {
        Write-LogMessage -Message "Creating remote directory on $($Session.ComputerName)" -Level Debug
        
        # Create the remote directory if it doesn't exist
        Invoke-Command -Session $Session -ScriptBlock {
            param($path)
            if (!(Test-Path -Path $path)) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
            }
            
            # Create Functions subdirectory if it doesn't exist
            $functionsPath = Join-Path -Path $path -ChildPath "Functions"
            if (!(Test-Path -Path $functionsPath)) {
                New-Item -Path $functionsPath -ItemType Directory -Force | Out-Null
            }
        } -ArgumentList $RemoteModulePath
        
        Write-LogMessage -Message "Copying module files to $($Session.ComputerName)" -Level Debug
        
        # Copy the module files
        Copy-Item -Path "$LocalModulePath\*" -Destination $RemoteModulePath -ToSession $Session -Recurse -Force
        
        # Create subnet.txt in the functions directory with subnet value
        $remoteSubnetPath = Join-Path -Path $RemoteModulePath -ChildPath "Functions\subnet.txt"
        
        Write-LogMessage -Message "Creating subnet.txt with value '$SubnetValue' on $($Session.ComputerName)" -Level Debug
        
        Invoke-Command -Session $Session -ScriptBlock {
            param($path, $content)
            Set-Content -Path $path -Value $content -Force
        } -ArgumentList $remoteSubnetPath, $SubnetValue
        
        # Verify remote directory structure and files
        $remoteVerification = Invoke-Command -Session $Session -ScriptBlock {
            param($path)
            
            $modulePsd1Path = Join-Path -Path $path -ChildPath "SystemInventory.psd1"
            $modulePsm1Path = Join-Path -Path $path -ChildPath "SystemInventory.psm1"
            $functionsPath = Join-Path -Path $path -ChildPath "Functions"
            $subnetPath = Join-Path -Path $functionsPath -ChildPath "subnet.txt"
            
            return @{
                ModuleExists = Test-Path -Path $path
                Psd1Exists = Test-Path -Path $modulePsd1Path
                Psm1Exists = Test-Path -Path $modulePsm1Path
                FunctionsExists = Test-Path -Path $functionsPath
                SubnetExists = Test-Path -Path $subnetPath
                FunctionsFiles = if (Test-Path -Path $functionsPath) {
                    (Get-ChildItem -Path $functionsPath -Filter "*.ps1").Name
                } else {
                    @()
                }
            }
        } -ArgumentList $RemoteModulePath
        
        if (-not $remoteVerification.ModuleExists) {
            Write-LogMessage -Message "Remote module directory does not exist after copy operation" -Level Warning
        }
        
        if (-not $remoteVerification.Psd1Exists) {
            Write-LogMessage -Message "SystemInventory.psd1 does not exist after copy operation" -Level Warning
        }
        
        if (-not $remoteVerification.Psm1Exists) {
            Write-LogMessage -Message "SystemInventory.psm1 does not exist after copy operation" -Level Warning
        }
        
        if (-not $remoteVerification.FunctionsExists) {
            Write-LogMessage -Message "Remote Functions directory does not exist after copy operation" -Level Warning
        }
        
        if (-not $remoteVerification.SubnetExists) {
            Write-LogMessage -Message "Remote subnet.txt does not exist after creation" -Level Warning
        }
        
        Write-LogMessage -Message "Function files found in remote Functions directory: $($remoteVerification.FunctionsFiles -join ', ')" -Level Info
        
        Write-LogMessage -Message "Successfully copied module to $($Session.ComputerName)" -Level Success
        return $true
    }
    catch {
        Write-LogMessage -Message "Failed to copy module to $($Session.ComputerName): $_" -Level Error
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
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 10
    )
    
    try {
        Write-LogMessage -Message "Starting inventory collection on $($Session.ComputerName)" -Level Debug
        
        $result = Invoke-Command -Session $Session -ScriptBlock {
            param($modulePath, $timeout)
            
            # Set execution policy for current process
            Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
            
            # Verify the module files
            $psd1Path = Join-Path -Path $modulePath -ChildPath "SystemInventory.psd1"
            $functionsDir = Join-Path -Path $modulePath -ChildPath "Functions"
            
            # Debug information
            Write-Verbose "Module directory: $modulePath (Exists: $(Test-Path $modulePath))"
            Write-Verbose "PSD1 file: $psd1Path (Exists: $(Test-Path $psd1Path))"
            Write-Verbose "Functions directory: $functionsDir (Exists: $(Test-Path $functionsDir))"
            
            if (Test-Path $functionsDir) {
                Write-Verbose "Functions directory contents:"
                Get-ChildItem -Path $functionsDir | ForEach-Object {
                    Write-Verbose "  - $($_.Name) (Size: $($_.Length) bytes)"
                }
            }
            
            # Load all functions manually to avoid module import issues
            try {
                # First, manually dot-source all PS1 files in the Functions directory
                Get-ChildItem -Path $functionsDir -Filter "*.ps1" | ForEach-Object {
                    Write-Verbose "Loading function file: $($_.FullName)"
                    . $_.FullName
                }
                
                # Verify functions are loaded
                $loadedFunctions = @(
                    "Get-SystemBasicInfo",
                    "Get-BiosInfo",
                    "Get-MotherboardInfo",
                    "Get-ProcessorInfo",
                    "Get-NetworkInfo",
                    "Get-StorageInfo",
                    "Get-MemoryInfo",
                    "Get-SystemInventory",
                    "Export-SystemInventory"
                )
                
                foreach ($function in $loadedFunctions) {
                    $functionExists = Get-Command -Name $function -ErrorAction SilentlyContinue
                    Write-Verbose "Function $function exists: $($null -ne $functionExists)"
                }
                
                # Now that functions are loaded, run Export-SystemInventory
                Write-Verbose "Running Export-SystemInventory"
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
            catch {
                return @{
                    Success = $false
                    FilePath = $null
                    ErrorMessage = "Error: $_"
                }
            }
        } -ArgumentList $RemoteModulePath, $TimeoutMinutes -Verbose
        
        if ($result.Success) {
            Write-LogMessage -Message "Successfully ran inventory collection on $($Session.ComputerName)" -Level Success
        }
        else {
            Write-LogMessage -Message "Failed to run inventory collection on $($Session.ComputerName): $($result.ErrorMessage)" -Level Error
        }
        
        return $result
    }
    catch {
        Write-LogMessage -Message "Error executing remote inventory collection on $($Session.ComputerName): $_" -Level Error
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
        [string]$LocalOutputPath
    )
    
    try {
        Write-LogMessage -Message "Copying inventory file from $($Session.ComputerName)" -Level Debug
        
        # Get just the filename
        $fileName = Split-Path -Path $RemoteFilePath -Leaf
        $localFilePath = Join-Path -Path $LocalOutputPath -ChildPath $fileName
        
        # Copy the file
        Copy-Item -Path $RemoteFilePath -Destination $localFilePath -FromSession $Session -Force
        
        # Verify the file exists locally
        if (Test-Path -Path $localFilePath) {
            Write-LogMessage -Message "Successfully copied inventory file from $($Session.ComputerName) to $localFilePath" -Level Success
            return @{
                Success = $true
                LocalPath = $localFilePath
                ErrorMessage = $null
            }
        }
        else {
            Write-LogMessage -Message "Failed to copy inventory file from $($Session.ComputerName): File not found after copy" -Level Error
            return @{
                Success = $false
                LocalPath = $null
                ErrorMessage = "File not found after copy operation"
            }
        }
    }
    catch {
        Write-LogMessage -Message "Error copying inventory file from $($Session.ComputerName): $_" -Level Error
        return @{
            Success = $false
            LocalPath = $null
            ErrorMessage = $_.ToString()
        }
    }
}

function Clear-RemoteSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession]$Session,
        
        [Parameter(Mandatory = $true)]
        [string]$RemoteModulePath,
        
        [Parameter(Mandatory = $false)]
        [string]$RemoteFilePath = $null
    )
    
    try {
        Write-LogMessage -Message "Cleaning up remote files on $($Session.ComputerName)" -Level Debug
        
        # Remove the module directory and JSON file if they exist
        Invoke-Command -Session $Session -ScriptBlock {
            param($modulePath, $filePath)
            
            # Remove the module directory
            if (Test-Path -Path $modulePath) {
                Remove-Item -Path $modulePath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Remove the JSON file if it exists
            if ($filePath -and (Test-Path -Path $filePath)) {
                Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
            }
        } -ArgumentList $RemoteModulePath, $RemoteFilePath
        
        Write-LogMessage -Message "Successfully cleaned up temporary files on $($Session.ComputerName)" -Level Info
        return $true
    }
    catch {
        Write-LogMessage -Message "Failed to clean up temporary files on $($Session.ComputerName): $_" -Level Warning
        return $false
    }
}

# Main script execution
try {
    # Write script start message
    Write-LogMessage -Message "Starting Physical System Inventory Collection" -Level Info
    Write-LogMessage -Message "Input CSV: $CsvPath" -Level Info
    Write-LogMessage -Message "Configuration: $ConfigPath" -Level Info
    Write-LogMessage -Message "Output directory: $OutputPath" -Level Info
    
    # Check if CSV exists
    if (-not (Test-Path -Path $CsvPath)) {
        Write-LogMessage -Message "CSV file not found: $CsvPath" -Level Error
        exit 1
    }
    
    # Check if config file exists
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-LogMessage -Message "Configuration file not found: $ConfigPath" -Level Error
        exit 1
    }
    
    # Load configuration
    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        
        # Validate configuration
        if (-not $config.Credentials -or -not $config.ModuleSettings -or -not $config.Subnet) {
            Write-LogMessage -Message "Invalid configuration file: Missing required sections" -Level Error
            exit 1
        }
        
        # Set default values if not present
        if (-not $config.Execution.RetryCount) {
            $config.Execution = @{} | Add-Member -MemberType NoteProperty -Name "RetryCount" -Value 3 -PassThru
        }
        
        if (-not $config.Execution.ExecutionTimeoutMinutes) {
            $config.Execution | Add-Member -MemberType NoteProperty -Name "ExecutionTimeoutMinutes" -Value 10 -PassThru -Force
        }
    }
    catch {
        Write-LogMessage -Message "Error loading configuration: $_" -Level Error
        exit 1
    }
    
    # Configure WinRM trusted hosts
    if (-not (Set-WinRMTrustedHosts)) {
        Write-LogMessage -Message "Failed to configure WinRM trusted hosts, continuing anyway..." -Level Warning
    }
    
    # Create credential object
    $securePassword = ConvertTo-SecureString -String $config.Credentials.Password -AsPlainText -Force
    $credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.Credentials.Username, $securePassword
    
    # Import CSV data
    try {
        Write-LogMessage -Message "Importing CSV data" -Level Info
        $csvData = Import-Csv -Path $CsvPath
        
        # Validate CSV format
        if (-not ($csvData | Get-Member -Name "IPAddress" -MemberType NoteProperty) -or
            -not ($csvData | Get-Member -Name "IsVirtual" -MemberType NoteProperty) -or
            -not ($csvData | Get-Member -Name "WinRMResponse" -MemberType NoteProperty)) {
            
            Write-LogMessage -Message "Invalid CSV format: Missing required columns (IPAddress, IsVirtual, WinRMResponse)" -Level Error
            exit 1
        }
    }
    catch {
        Write-LogMessage -Message "Error importing CSV data: $_" -Level Error
        exit 1
    }
    
    # Filter for physical systems with WinRM enabled
    $physicalSystems = $csvData | Where-Object { 
        ($_.IsVirtual -eq $false -or $_.IsVirtual -eq "False") -and 
        ($_.WinRMResponse -eq $true -or $_.WinRMResponse -eq "True") 
    }
    
    $totalPhysical = $physicalSystems.Count
    
    Write-LogMessage -Message "Found $totalPhysical physical systems with WinRM enabled" -Level Info
    
    if ($totalPhysical -eq 0) {
        Write-LogMessage -Message "No physical systems found with WinRM enabled. Exiting." -Level Warning
        exit 0
    }
    
    # Process each physical system
    $results = @{
        Success = 0
        Failed = 0
        Details = @()
    }
    
    $processed = 0
    
    foreach ($system in $physicalSystems) {
        $ipAddress = $system.IPAddress
        
        $currentSystem = @{
            IPAddress = $ipAddress
            Status = "Processing"
            ErrorMessage = $null
            InventoryFile = $null
        }
        
        $processed++
        Write-LogMessage -Message "Processing physical system $ipAddress ($processed/$totalPhysical)" -Level Info
        
        # Create PS Session
        $session = $null
        $retry = 0
        $maxRetries = [int]$config.Execution.RetryCount
        
        while ($retry -le $maxRetries -and -not $session) {
            try {
                $session = New-PSSession -ComputerName $ipAddress -Credential $credentials -ErrorAction Stop -Authentication Negotiate
                Write-LogMessage -Message "Successfully established PSSession with $ipAddress" -Level Success
            }
            catch {
                $retry++
                if ($retry -le $maxRetries) {
                    Write-LogMessage -Message "Retry $retry/$maxRetries : Failed to connect to $ipAddress - $_" -Level Warning
                    Start-Sleep -Seconds 5
                }
                else {
                    Write-LogMessage -Message "Failed to connect to $ipAddress after $maxRetries retries: $_" -Level Error
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
        $moduleCopied = Copy-ModuleToRemoteSystem -Session $session -LocalModulePath $config.ModuleSettings.ModulePath -RemoteModulePath $config.ModuleSettings.TempRemotePath -SubnetValue $config.Subnet.BaseSubnet
        
        if (-not $moduleCopied) {
            $currentSystem.Status = "Failed"
            $currentSystem.ErrorMessage = "Failed to copy module"
            $results.Failed++
            $results.Details += $currentSystem
            Remove-PSSession -Session $session
            continue
        }
        
        # Run inventory collection
        $inventoryResult = Invoke-RemoteInventoryCollection -Session $session -RemoteModulePath $config.ModuleSettings.TempRemotePath -TimeoutMinutes $config.Execution.ExecutionTimeoutMinutes -Verbose
        
        if (-not $inventoryResult.Success) {
            $currentSystem.Status = "Failed"
            $currentSystem.ErrorMessage = "Inventory collection failed: $($inventoryResult.ErrorMessage)"
            $results.Failed++
            $results.Details += $currentSystem
            
            # Clean up and close session
            Clear-RemoteSystem -Session $session -RemoteModulePath $config.ModuleSettings.TempRemotePath
            Remove-PSSession -Session $session
            continue
        }
        
        # Copy inventory file to local system
        $copyResult = Copy-InventoryFileFromRemote -Session $session -RemoteFilePath $inventoryResult.FilePath -LocalOutputPath $OutputPath
        
        if (-not $copyResult.Success) {
            $currentSystem.Status = "Failed"
            $currentSystem.ErrorMessage = "Failed to copy inventory file: $($copyResult.ErrorMessage)"
            $results.Failed++
            $results.Details += $currentSystem
            
            # Clean up and close session
            Clear-RemoteSystem -Session $session -RemoteModulePath $config.ModuleSettings.TempRemotePath -RemoteFilePath $inventoryResult.FilePath
            Remove-PSSession -Session $session
            continue
        }
        
        # Clean up and close session
        Clear-RemoteSystem -Session $session -RemoteModulePath $config.ModuleSettings.TempRemotePath -RemoteFilePath $inventoryResult.FilePath
        Remove-PSSession -Session $session
        
        $currentSystem.Status = "Success"
        $currentSystem.InventoryFile = $copyResult.LocalPath
        $results.Success++
        $results.Details += $currentSystem
    }
    
    # Output summary
    Write-LogMessage -Message "Physical System Inventory Collection Summary:" -Level Info
    Write-LogMessage -Message "Total physical systems processed: $totalPhysical" -Level Info
    Write-LogMessage -Message "Successful: $($results.Success)" -Level Info
    Write-LogMessage -Message "Failed: $($results.Failed)" -Level Info
    Write-LogMessage -Message "Collection completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info
    
    # Export results to JSON
    $resultsFile = Join-Path -Path $OutputPath -ChildPath "CollectionResults-$timestamp.json"
    $results | ConvertTo-Json -Depth 3 | Out-File -FilePath $resultsFile
    
    Write-LogMessage -Message "Collection results saved to $resultsFile" -Level Success
    Write-LogMessage -Message "Physical System Inventory Collection completed" -Level Success
    
    exit 0
}
catch {
    Write-LogMessage -Message "Error in Physical System Inventory Collection: $_" -Level Error
    Write-LogMessage -Message "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}