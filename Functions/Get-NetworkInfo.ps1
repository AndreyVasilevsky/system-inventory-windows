function Get-NetworkInfo {
    [CmdletBinding()]
    param()
    
    try {
        $basicInfo = Get-SystemBasicInfo
        Get-WmiObject -Class Win32_NetworkAdapter | 
        Where-Object { $_.AdapterType -eq "Ethernet 802.3" } | 
        ForEach-Object {
            $controller = $_
            $pnpEntity = Get-WmiObject -Class Win32_PnPEntity | 
                Where-Object { $_.DeviceID -eq $controller.PNPDeviceID }
            
            # Get PCI information using WMI
            $pciInfo = Get-WmiObject -Class Win32_PnPSignedDriver |
                Where-Object { $_.DeviceID -eq $controller.PNPDeviceID }

            $pcieLinkSpeed = $null
            $pcieLinkWidth = $null

            try {
                $netAdapter = Get-NetAdapter | Where-Object { $_.InterfaceIndex -eq $controller.InterfaceIndex }
                $hardwareInfo = Get-NetAdapterHardwareInfo -Name $netAdapter.Name -ErrorAction Stop
                $pcieLinkSpeed = $hardwareInfo.PcieLinkSpeed
                $pcieLinkWidth = $hardwareInfo.PcieLinkWidth
                Write-Verbose "PCIe information for adapter '$($controller.Name)': Speed=$pcieLinkSpeed, Width=$pcieLinkWidth"
            }
            catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
                # Handle the specific error for non-existent adapters
                Write-Verbose "PCIe information not available for adapter '$($controller.Name)'"
            }
            catch {
                # Handle any other unexpected errors
                Write-Warning "Error getting PCIe information for adapter '$($controller.Name)': $_"
            }
            

            @{
                ethernet_controller_id = $null
                branding_name = $controller.ProductName
                cable_type = $null
                device_id = "0x" + ($pciInfo.DeviceID -split "\\" | Select-Object -Last 1)
                firmware = $controller.DriverVersion
                numa_node = $null  # Would need additional WMI query
                nvm_version = $null  # Would need vendor-specific tools
                pcie_speed_max = $pcieLinkSpeed  
                pcie_width_current = $pcieLinkWidth
                pcie_width_max = $null  
                pcie_functions = @(
                    @{
                        bus_device_function = $pciInfo.LocationInformation # May need formatting
                        ip_address = (Get-NetIPAddress | Where-Object { 
                            $_.InterfaceIndex -eq $controller.InterfaceIndex -and 
                            $_.AddressFamily -eq 'IPv4' 
                        }).IPAddress
                        mac_address = $controller.MACAddress -replace "-", ":"  # Format MAC with colons
                        is_management_port = ($controller.InterfaceIndex -eq $basicInfo.mgt_adapter_index)
                        pcie_speed_current = $pcieLinkSpeed
                        speed = (Get-NetAdapter -InterfaceIndex $controller.InterfaceIndex ).LinkSpeed  
                        connected_devices = $null
                    }
                )
                revision = "0x" + ($pciInfo.InfSection -split "\\" | Select-Object -Last 1)
                slot = $null
                subvendor_device_id = $null  # Would need PCI config space access
                subvendor_id = $null
                vendor_id = "0x" + ($pciInfo.HardWareID -split "VEN_" | Select-Object -Last 1).Substring(0,4)
                major_device_name = $null
                minor_device_name = $null
                vendor_name = $controller.Name.Split()[0] -replace '\(R\)', ''
                subvendor_name = $null
                codename = $null
                silicon_family_name = $null
            }
        }
    }
    catch {
        Write-Error "Error getting network info: $_"
        return $null
    }
}