# File: SystemInventory/Functions/Get-NetworkInfo.ps1
function Get-NetworkInfo {
    [CmdletBinding()]
    param()
    
    try {
        Get-WmiObject -Class Win32_NetworkAdapter | 
        Where-Object { $_.AdapterType -eq "Ethernet 802.3" } | 
        ForEach-Object {
            $controller = $_
            @{
                ethernet_controller_id = $null
                branding_name = $controller.ProductName
                device_id = "0x" + $controller.DeviceID
                firmware = $controller.ServiceName
                pcie_functions = @(
                    @{
                        bus_device_function = $null
                        ip_address = (Get-NetIPAddress | Where-Object { 
                            $_.InterfaceIndex -eq $controller.InterfaceIndex -and 
                            $_.AddressFamily -eq 'IPv4' 
                        }).IPAddress
                        is_management_port = $false
                        mac_address = $controller.MACAddress
                        speed = $controller.Speed
                    }
                )
            }
        }
    }
    catch {
        Write-Error "Error getting network info: $_"
        return $null
    }
}