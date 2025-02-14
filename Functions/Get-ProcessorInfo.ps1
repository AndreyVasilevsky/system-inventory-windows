# File: SystemInventory/Functions/Get-ProcessorInfo.ps1
function Get-ProcessorInfo {
    [CmdletBinding()]
    param()
    
    try {
        Get-WmiObject -Class Win32_Processor | ForEach-Object {
            @{
                cpu_id = $null
                core_count = $_.NumberOfCores
                family = $_.Family
                max_speed_mhz = $_.MaxClockSpeed
                min_speed_mhz = $null
                model = $_.Model
                product = $_.Name
                socket_designation = $_.SocketDesignation
                socket_type = "Socket " + $_.UpgradeMethod
                stepping = $_.Stepping
                thread_count = $_.NumberOfLogicalProcessors
                manufacturer = if ($_.Manufacturer -like "Intel") { "Intel" } else { if ($_.Manufacturer -like "AMD") { "AMD" } else { $_.Manufacturer } }
            }
        }
    }
    catch {
        Write-Error "Error getting processor info: $_"
        return $null
    }
}