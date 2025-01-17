# File: SystemInventory/Functions/Get-StorageInfo.ps1
function Get-StorageInfo {
    [CmdletBinding()]
    param()
    
    try {
        Get-WmiObject -Class Win32_DiskDrive | ForEach-Object {
            @{
                hard_drive_id = $null
                manufacturer = $_.Manufacturer
                model = $_.Model
                serial_number = $_.SerialNumber
                size_gb = [math]::Round($_.Size / 1GB, 2)
            }
        }
    }
    catch {
        Write-Error "Error getting storage info: $_"
        return $null
    }
}