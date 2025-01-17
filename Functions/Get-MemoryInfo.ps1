# File: SystemInventory/Functions/Get-MemoryInfo.ps1
function Get-MemoryInfo {
    [CmdletBinding()]
    param()
    
    try {
        Get-WmiObject -Class Win32_PhysicalMemory | ForEach-Object {
            @{
                memory_bank_id = $null
                description = $_.MemoryType
                manufacturer = $_.Manufacturer
                product_string = $_.PartNumber
                size_gb = [math]::Round($_.Capacity / 1GB, 2)
                slot = $_.DeviceLocator
                speed_mts = $_.Speed
            }
        }
    }
    catch {
        Write-Error "Error getting memory info: $_"
        return $null
    }
}
