# File: SystemInventory/Functions/Get-BiosInfo.ps1
function Get-BiosInfo {
    [CmdletBinding()]
    param()
    
    try {
        $bios = Get-WmiObject -Class Win32_BIOS
        
        @{
            date = if ($bios.ReleaseDate) { 
                [System.Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate).ToString("yyyy-MM-ddTHH:mm:ss-00:00")
            } else {
                $null
            }
            vendor = $bios.Manufacturer
            version = $bios.SMBIOSBIOSVersion
            vtd_enabled = $null
            vtx_enabled = $null
        }
    }
    catch {
        Write-Error "Error getting BIOS info: $_"
        return $null
    }
}