# File: SystemInventory/Functions/Get-SystemBasicInfo.ps1
function Get-SystemBasicInfo {
    [CmdletBinding()]
    param()
    
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        
        @{
            system_id = $null
            system_name = $env:COMPUTERNAME
            created_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            description = $null
            manufacturer = $computerSystem.Manufacturer
            mgt_ip_address = (Get-NetIPAddress | Where-Object { 
                $_.AddressFamily -eq 'IPv4' } | Where-Object { $_.ipaddress -like "10.*"}).IPAddress
            mgt_adapter_index = (Get-NetIPAddress -AddressFamily ipv4 | Where-Object { $_.ipaddress -like "10.*"}).InterfaceIndex
            mgt_mac_address = (Get-NetAdapter -InterfaceIndex (Get-NetIPAddress -AddressFamily ipv4 | Where-Object { $_.ipaddress -like "10.*"}).InterfaceIndex).MacAddress -replace "-", ":"
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