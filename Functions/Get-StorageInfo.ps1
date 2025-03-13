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
                size_gb = [int]($_.Size / 1GB)  # Convert to integer by truncating decimal
                hard_drive_type = $null
                port_form_factor = $null
            }
        }
    }
    catch {
        Write-Error "Error getting storage info: $_"
        return $null
    }
}