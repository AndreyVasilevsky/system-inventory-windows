# File: SystemInventory/Functions/Get-NetworkInfo.ps1
function Get-NetworkInfo {
    [CmdletBinding()]
    param()
    
    try {
        # Initialize with empty array to avoid null reference
        $results = @()
        
        $basicInfo = Get-SystemBasicInfo
        if ($null -eq $basicInfo) {
            Write-Warning "Basic system info not available"
            return $results
        }
        
        # Use try-catch around each WMI query to handle errors
        try {
            $networkAdapters = @(Get-WmiObject -Class Win32_NetworkAdapter -ErrorAction Stop | 
                Where-Object { 
                    $_.AdapterType -eq "Ethernet 802.3" -and
                    $_.Name -notmatch "VMware|VirtualBox|Hyper-V|Virtual Adapter|vEthernet" -and
                    $_.Name -notmatch "WAN Miniport|Microsoft Kernel|Miniport|PANGP|VPN" -and
                    $_.Manufacturer -notmatch "Microsoft|VMware|Oracle|Parallel|Citrix"
                })
        }
        catch {
            Write-Warning "Failed to query network adapters: $_"
            return $results
        }
            
        # Always return an array, even if empty
        $results = @()
        
        # Check if we have any adapters
        if ($null -eq $networkAdapters -or @($networkAdapters).Count -eq 0) {
            Write-Warning "No physical network adapters found."
            return $results  # Return empty array
        }
        
        foreach ($controller in $networkAdapters) {
            Write-Verbose "Processing network adapter: $($controller.Name)"
            
            # Skip virtual adapters by manufacturer or description
            if ($controller.Name -match "VMware|VirtualBox|Hyper-V|Virtual|WAN Miniport|Microsoft Kernel|Miniport|PANGP|VPN" -or
                $controller.Description -match "VMware|VirtualBox|Hyper-V|Virtual|WAN Miniport|Microsoft Kernel|Miniport" -or
                $controller.Manufacturer -match "VMware|Microsoft|Oracle|Parallels|Citrix" -or
                $controller.PNPDeviceID -match "ROOT\\") {
                Write-Verbose "Skipping virtual adapter: $($controller.Name)"
                continue
            }
            
            # Get PCI information using Win32_PnPSignedDriver
            $pciInfo = Get-WmiObject -Class Win32_PnPSignedDriver |
                Where-Object { $_.DeviceID -eq $controller.PNPDeviceID }
                
            if (-not $pciInfo) {
                Write-Verbose "No PCI information found for adapter $($controller.Name)"
                continue
            }
            
            # Skip if no physical PCI info (likely virtual)
            $pciIdFormat = $pciInfo.HardwareID | Where-Object { $_ -match 'PCI\\VEN_' } | Select-Object -First 1
            if (-not $pciIdFormat) {
                Write-Verbose "Skipping adapter with no PCI information: $($controller.Name)"
                continue
            }
            
            # Debugging - show what hardware IDs we have
            Write-Verbose "Hardware IDs for $($controller.Name):"
            foreach ($id in $pciInfo.HardwareID) {
                Write-Verbose "  $id"
            }
            
            Write-Verbose "Using PCI ID: $pciIdFormat"
            
            # Extract vendor ID (VEN_XXXX)
            $vendorId = if ($pciIdFormat -match 'VEN_([0-9A-F]{4})') {
                "0x$($Matches[1].ToLower())"
            } else { "0x0000" }
            
            # Extract device ID (DEV_XXXX)
            $deviceId = if ($pciIdFormat -match 'DEV_([0-9A-F]{4})') {
                "0x$($Matches[1].ToLower())"
            } else { "0x0000" }
            
            # Extract subsystem information (SUBSYS_XXXXXXXX)
            # SUBSYS format is typically SUBSYS_SSSSDDDD where SSSS is subsystem vendor and DDDD is subsystem device
            $subVendorId = if ($pciIdFormat -match 'SUBSYS_([0-9A-F]{4})') {
                "0x$($Matches[1].ToLower())"
            } else { "0x0000" }
            
            $subDeviceId = if ($pciIdFormat -match 'SUBSYS_[0-9A-F]{4}([0-9A-F]{4})') {
                "0x$($Matches[1].ToLower())"
            } else { "0x0000" }
            
            # Extract revision (REV_XX)
            $revision = if ($pciIdFormat -match 'REV_([0-9A-F]{2})') {
                "0x$($Matches[1].ToLower())"
            } else { "0x00" }
            
            Write-Verbose "Extracted values:"
            Write-Verbose "  Vendor ID: $vendorId"
            Write-Verbose "  Device ID: $deviceId"
            Write-Verbose "  SubVendor ID: $subVendorId"
            Write-Verbose "  SubDevice ID: $subDeviceId"
            Write-Verbose "  Revision: $revision"
            
            # Get PCIe information if available
            $pcieLinkSpeed = $null
            $pcieLinkWidth = $null
            
            try {
                $netAdapter = Get-NetAdapter | Where-Object { $_.InterfaceIndex -eq $controller.InterfaceIndex }
                if ($netAdapter) {
                    $hardwareInfo = Get-NetAdapterHardwareInfo -Name $netAdapter.Name -ErrorAction Stop
                    $pcieLinkSpeed = $hardwareInfo.PcieLinkSpeed
                    $pcieLinkWidth = $hardwareInfo.PcieLinkWidth
                }
            }
            catch {
                Write-Verbose "PCIe information not available for adapter '$($controller.Name)': $_"
            }
            
            # Get IP addresses associated with this adapter
            $ipAddresses = @()
            try {
                $ipAddresses = Get-NetIPAddress | Where-Object { 
                    $_.InterfaceIndex -eq $controller.InterfaceIndex -and 
                    $_.AddressFamily -eq 'IPv4' 
                } | Select-Object -ExpandProperty IPAddress
            }
            catch {
                Write-Verbose "Error getting IP addresses: $_"
            }
            
            # Get connection speed
            $connectionSpeed = $null
            try {
                $netAdapterInfo = Get-NetAdapter -InterfaceIndex $controller.InterfaceIndex -ErrorAction SilentlyContinue
                if ($netAdapterInfo) {
                    $connectionSpeed = $netAdapterInfo.LinkSpeed
                }
            }
            catch {
                Write-Verbose "Error getting connection speed: $_"
            }
            
            # Create the network adapter object
            $adapterInfo = @{
                ethernet_controller_id = $null
                branding_name = $controller.ProductName
                cable_type = $null
                device_id = $deviceId
                firmware = $controller.DriverVersion
                numa_node = $null
                nvm_version = $null
                pcie_speed_max = $pcieLinkSpeed
                pcie_width_current = $pcieLinkWidth
                pcie_width_max = $null
                pcie_functions = @(
                    @{
                        bus_device_function = $controller.PNPDeviceID
                        ip_address = if ($ipAddresses.Count -gt 0) { $ipAddresses[0] } else { $null }
                        is_management_port = ($controller.InterfaceIndex -eq $basicInfo.mgt_adapter_index)
                        mac_address = $controller.MACAddress -replace "-", ":"
                        pcie_speed_current = $pcieLinkSpeed
                        speed = $connectionSpeed
                        connected_devices = $null
                    }
                )
                revision = $revision
                slot = $null
                subvendor_device_id = $subDeviceId
                subvendor_id = $subVendorId
                vendor_id = $vendorId
                major_device_name = $null
                minor_device_name = $null
                vendor_name = $pciInfo.Manufacturer
                subvendor_name = $null
                codename = $null
                silicon_family_name = $null
            }
            
            $results += $adapterInfo
        }
        
        return $results
    }
    catch {
        Write-Error "Error getting network info: $_"
        # Return empty array instead of null to prevent errors
        return @()
    }
}