# File: SystemInventory/Functions/Get-SystemInventory.ps1
function Get-SystemInventory {
    [CmdletBinding()]
    param()
    
    try {
        # Get basic system info first
        $basicInfo = Get-SystemBasicInfo
        if ($null -eq $basicInfo) {
            throw "Failed to get basic system information"
        }
        
        # Initialize other components with empty arrays to avoid null references
        $biosInfo = Get-BiosInfo
        $mbInfo = Get-MotherboardInfo
        $cpuInfo = @(Get-ProcessorInfo)
        $storageInfo = @(Get-StorageInfo)
        $memoryInfo = @(Get-MemoryInfo)
        
        # Get network info - handle null result specially
        $networkInfo = $null
        try {
            $networkInfo = @(Get-NetworkInfo)
        }
        catch {
            Write-Warning "Error getting network info: $_"
            $networkInfo = @()
        }
        
        # Ensure we have arrays even if the functions return null
        if ($null -eq $cpuInfo) { $cpuInfo = @() }
        if ($null -eq $storageInfo) { $storageInfo = @() }
        if ($null -eq $memoryInfo) { $memoryInfo = @() }
        if ($null -eq $networkInfo) { $networkInfo = @() }

        # Build the inventory object
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
                manufacturer = $basicInfo.manufacturer
                mgt_ip_address = $basicInfo.mgt_ip_address
                mgt_mac_address = $basicInfo.mgt_mac_address
                name_model = $basicInfo.name_model
                pools = @("infrastructure")
                serial_number = $basicInfo.serial_number
                sku = "SKU=0000;ModelName=$($basicInfo.name_model)"
                uuid = $basicInfo.uuid
                version = "Not Specified"
                inventory_id = $null
                bmc = @{
                    firmware_revision = $null
                    guid = $basicInfo.uuid
                    ip_address = $null
                    mac_address = $null
                    manufacturer = $basicInfo.manufacturer
                    vlan = 0
                    user = $null
                    password = $null
                }
                motherboard = $mbInfo
                status = $null
                bios = $biosInfo
                cpus = $cpuInfo
                ethernet_controllers = $networkInfo
                hard_drives = $storageInfo
                kvm = $null
                kvm_dongle_serial_number = $null
                kvm_node_group = $null
                kvm_node_interface_label = $null
                kvm_node_label = $null
                link_partner_system_ids = $null
                memory_banks = $memoryInfo
                extended_fields = $null
                pdus = $null
                power_options = $null
                display_name = $null
            }
            schema_metadata = @{
                schema_version = "v0.1"
                origin = "Andrey's Inventory Script - Windows"
            }
        }

        return $inventory
    }
    catch {
        Write-Error "Error getting system inventory: $_"
        return $null
    }
}