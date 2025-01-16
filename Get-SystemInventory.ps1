# System Inventory Collection Script
# This script collects detailed system information and outputs it to a JSON file

function Get-SystemInventory {
    $systemInfo = @{
        system = @{
            system_id = $null
            system_name = $env:COMPUTERNAME
            created_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            description = $null
            manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
            mgt_ip_address = (Get-NetIPAddress | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.PrefixOrigin -eq 'Dhcp' }).IPAddress
            mgt_mac_address = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })[0].MacAddress
            name_model = (Get-WmiObject -Class Win32_ComputerSystem).Model
            serial_number = (Get-WmiObject -Class Win32_BIOS).SerialNumber
            uuid = (Get-WmiObject -Class Win32_ComputerSystemProduct).UUID
            version = (Get-WmiObject -Class Win32_OperatingSystem).Version
        }
        bios = @{
            # date = ((Get-WmiObject -Class Win32_BIOS).ReleaseDate).ToString("yyyy-MM-ddTHH:mm:ss-00:00")
            
            vendor = (Get-WmiObject -Class Win32_BIOS).Manufacturer
            version = (Get-WmiObject -Class Win32_BIOS).SMBIOSBIOSVersion
            vtd_enabled = $null  # Requires additional detection logic
            vtx_enabled = $null  # Requires additional detection logic
        }
        motherboard = @{
            motherboard_id = $null
            product = (Get-WmiObject -Class Win32_BaseBoard).Product
            serial_number = (Get-WmiObject -Class Win32_BaseBoard).SerialNumber
            vendor = (Get-WmiObject -Class Win32_BaseBoard).Manufacturer
            version = (Get-WmiObject -Class Win32_BaseBoard).Version
        }
        cpus = @(
            Get-WmiObject -Class Win32_Processor | ForEach-Object {
                @{
                    cpu_id = $null
                    core_count = $_.NumberOfCores
                    family = $_.Family
                    max_speed_mhz = $_.MaxClockSpeed
                    min_speed_mhz = $null
                    model = $_.Model
                    product = $_.Name
                    socket_designation = $_.SocketDesignation
                    socket_type = "Socket " + $_.UpgradeMethod
                    stepping = $_.Stepping
                    thread_count = $_.NumberOfLogicalProcessors
                    manufacturer = $_.Manufacturer
                }
            }
        )
        ethernet_controllers = @(
            Get-WmiObject -Class Win32_NetworkAdapter | Where-Object { $_.AdapterType -eq "Ethernet 802.3" } | ForEach-Object {
                $controller = $_
                @{
                    ethernet_controller_id = $null
                    branding_name = $controller.ProductName
                    device_id = "0x" + $controller.DeviceID
                    firmware = $controller.ServiceName
                    pcie_functions = @(
                        @{
                            bus_device_function = $null
                            ip_address = (Get-NetIPAddress | Where-Object { $_.InterfaceIndex -eq $controller.InterfaceIndex -and $_.AddressFamily -eq 'IPv4' }).IPAddress
                            is_management_port = $false
                            mac_address = $controller.MACAddress
                            speed = $controller.Speed
                        }
                    )
                }
            }
        )
        hard_drives = @(
            Get-WmiObject -Class Win32_DiskDrive | ForEach-Object {
                @{
                    hard_drive_id = $null
                    manufacturer = $_.Manufacturer
                    model = $_.Model
                    serial_number = $_.SerialNumber
                    size_gb = [math]::Round($_.Size / 1GB, 2)
                }
            }
        )
        memory_banks = @(
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
        )
    }

    # Add schema metadata
    $inventory = @{
        system = $systemInfo.system
        schema_metadata = @{
            schema_version = "v0.1"
            origin = "Auto-Inventory Tool"
        }
        bios = $systemInfo.bios
        motherboard = $systemInfo.motherboard
        cpus = $systemInfo.cpus
        ethernet_controllers = $systemInfo.ethernet_controllers
        hard_drives = $systemInfo.hard_drives
        memory_banks = $systemInfo.memory_banks
    }

    return $inventory
}

# Generate the inventory
$inventory = Get-SystemInventory

# Create filename using MAC address
$macAddress = $inventory.system.mgt_mac_address -replace ':', '-'
$fileName = "auto_inventory_$macAddress.json"

# Export to JSON file
$inventory | ConvertTo-Json -Depth 10 | Out-File $fileName

Write-Host "Inventory has been saved to $fileName"