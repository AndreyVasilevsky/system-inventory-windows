# File: SystemInventory/Functions/Get-ProcessorInfo.ps1
function Get-ProcessorInfo {
    [CmdletBinding()]
    param()
    
    try {
        Get-WmiObject -Class Win32_Processor | ForEach-Object {
            # Normalize manufacturer name
            $manufacturer = 
                if ($_.Manufacturer -like "*Intel*" -or $_.Manufacturer -like "*GenuineIntel*") { 
                    "Intel" 
                } 
                elseif ($_.Manufacturer -like "*AMD*" -or $_.Manufacturer -like "*AuthenticAMD*") { 
                    "AMD" 
                } 
                else { 
                    $_.Manufacturer 
                }
            
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
                manufacturer = $manufacturer
                codename = $null
                pcie_gen = $null
                silicon_family_name = $null
            }
        }
    }
    catch {
        Write-Error "Error getting processor info: $_"
        return $null
    }
}