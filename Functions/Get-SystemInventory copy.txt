# System Inventory Collection Script
# Outputs JSON file matching auto_inventory format

# Function to get CPU information
function Get-CPUInfo {
    $cpus = Get-CimInstance Win32_Processor
    $cpuArray = @()
    
    foreach ($cpu in $cpus) {
        $cpuInfo = @{
            cpu_id = $null
            core_count = $cpu.NumberOfCores
            family = $cpu.Family
            max_speed_mhz = $cpu.MaxClockSpeed
            min_speed_mhz = $null
            model = $cpu.Model
            product = $cpu.Name
            socket_designation = $cpu.SocketDesignation
            socket_type = $cpu.UpgradeMethod
            stepping = $cpu.Stepping
            thread_count = $cpu.NumberOfLogicalProcessors
            manufacturer = $cpu.Manufacturer
            codename = $null
            pcie_gen = $null
            silicon_family_name = $null
        }
        $cpuArray += $cpuInfo
    }
    return $cpuArray
}

# Function to get memory information
function Get-MemoryInfo {
    $memoryBanks = Get-CimInstance Win32_PhysicalMemory
    $memoryArray = @()
    
    foreach ($memory in $memoryBanks) {
        $memoryInfo = @{
            memory_bank_id = $null
            description = $memory.Description
            manufacturer = $memory.Manufacturer
            product_string = $memory.PartNumber.Trim()
            size_gb = [math]::Round($memory.Capacity / 1GB)
            slot = $memory.DeviceLocator
            speed_mts = $memory.Speed
        }
        $memoryArray += $memoryInfo
    }
    return $memoryArray
}

# Function to get network adapter information
function Get-NetworkInfo {
    $nics = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true }
    $nicArray = @()
    
    foreach ($nic in $nics) {
        $nicConfig = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.Index -eq $nic.Index }
        $pciePath = Get-CimInstance Win32_PnPEntity | Where-Object { $_.DeviceID -eq $nic.PNPDeviceID }
        
        $nicInfo = @{
            ethernet_controller_id = $null
            branding_name = $nic.Name
            cable_type = $null
            device_id = "0x" + $nic.DeviceID.Split("\")[-1].Split("&")[0]
            firmware = $nic.DriverVersion
            numa_node = 0
            nvm_version = $null
            pcie_speed_max = $null
            pcie_width_current = $null
            pcie_width_max = $null
            pcie_functions = @(
                @{
                    bus_device_function = $null
                    ip_address = $nicConfig.IPAddress[0]
                    is_management_port = $false
                    mac_address = $nicConfig.MACAddress.ToLower()
                    pcie_speed_current = $null
                    speed = "$($nic.Speed/1000000)Mbit/s"
                    connected_devices = $null
                }
            )
            revision = $null
            slot = $null
            subvendor_device_id = $null
            subvendor_id = $null
            vendor_id = $null
            major_device_name = $null
            minor_device_name = $null
            vendor_name = $null
            subvendor_name = $null
            codename = $null
            silicon_family_name = $null
        }
        $nicArray += $nicInfo
    }
    return $nicArray
}

# Function to get storage information
function Get-StorageInfo {
    $drives = Get-CimInstance Win32_DiskDrive
    $driveArray = @()
    
    foreach ($drive in $drives) {
        $driveInfo = @{
            hard_drive_id = $null
            manufacturer = $drive.Manufacturer
            model = $drive.Model
            serial_number = $drive.SerialNumber
            size_gb = [math]::Round($drive.Size / 1GB)
            hard_drive_type = $null
            port_form_factor = $null
        }
        $driveArray += $driveInfo
    }
    return $driveArray
}

# Function to get BIOS information
function Get-BiosInfo {
    $bios = Get-CimInstance Win32_BIOS
    return @{
        date = (Get-Date $bios.ReleaseDate).ToString("yyyy-MM-ddTHH:mm:ss-00:00")
        vendor = $bios.Manufacturer
        version = $bios.SMBIOSBIOSVersion
        vtd_enabled = $null  # Would need additional WMI queries to get virtualization settings
        vtx_enabled = $null
    }
}

# Function to get BMC information (if available)
function Get-BMCInfo {
    # Note: This might require specific vendor tools or IPMI access
    return @{
        firmware_revision = $null
        guid = $null
        ip_address = $null
        mac_address = $null
        manufacturer = $null
        vlan = 0
        user = $null
        password = $null
    }
}

# Main inventory collection
$system = Get-CimInstance Win32_ComputerSystem
$motherboard = Get-CimInstance Win32_BaseBoard

# Create the main inventory object
$inventory = @{
    system = @{
        system_id = $null
        system_name = $env:COMPUTERNAME
        created_date = $null
        description = $null
        lab = $null
        lab_row_rack = $null
        lab_row_rack_id = $null
        lab_rack_slot = $null
        manufacturer = $system.Manufacturer
        mgt_ip_address = $null
        mgt_mac_address = (Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true } | Select-Object -First 1).MACAddress.ToLower()
        name_model = $system.Model
        pools = @("infrastructure")
        serial_number = $system.SerialNumber
        sku = "SKU=0000;ModelName=$($system.Model)"
        uuid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
        version = "Not Specified"
        inventory_id = $null
        bmc = Get-BMCInfo
        motherboard = @{
            motherboard_id = $null
            cpu_numa_count = (Get-CimInstance Win32_Processor).Count
            cpu_sockets_count = (Get-CimInstance Win32_Processor).Count
            product = $motherboard.Product
            serial_number = $motherboard.SerialNumber
            vendor = $motherboard.Manufacturer
            version = $motherboard.Version
        }
        status = $null
        bios = Get-BiosInfo
        cpus = Get-CPUInfo
        ethernet_controllers = Get-NetworkInfo
        hard_drives = Get-StorageInfo
        memory_banks = Get-MemoryInfo
        kvm = $null
        extended_fields = $null
        pdus = $null
        power_options = $null
        display_name = $null
    }
    schema_metadata = @{
        schema_version = "v0.1"
        origin = "Auto-Inventory Tool"
    }
}

# Generate unique filename using MAC address
$macAddress = $inventory.system.mgt_mac_address.Replace(":", "-")
$outputFile = "auto_inventory_$macAddress.json"

# Convert to JSON and save to file
$inventory | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8

Write-Host "Inventory has been saved to $outputFile"