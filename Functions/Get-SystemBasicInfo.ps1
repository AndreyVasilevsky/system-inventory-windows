# File: SystemInventory/Functions/Get-SystemBasicInfo.ps1
function Get-SystemBasicInfo {
    [CmdletBinding()]
    param()
    
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        $networkAdapter = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })[0]
        
        @{
            system_id = $null
            system_name = $env:COMPUTERNAME
            created_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            description = $null
            manufacturer = $computerSystem.Manufacturer
            mgt_ip_address = (Get-NetIPAddress | Where-Object { 
                $_.AddressFamily -eq 'IPv4' -and $_.PrefixOrigin -eq 'Dhcp' 
            }).IPAddress
            mgt_mac_address = $networkAdapter.MacAddress
            name_model = $computerSystem.name_model
            serial_number = (Get-WmiObject -Class Win32_BIOS).SerialNumber
            uuid = (Get-WmiObject -Class Win32_ComputerSystemProduct).UUID
        }
    }
    catch {
        Write-Error "Error getting system basic info: $_"
        return $null
    }
}