# File: SystemInventory/Functions/Get-SystemInventory.ps1
function Get-SystemInventory {
    [CmdletBinding()]
    param()
    
    try {
        $systemInfo = @{
            basicInfo = Get-SystemBasicInfo
            bios = Get-BiosInfo
            mb = Get-MotherboardInfo
            cpus = @(Get-ProcessorInfo)
            ethernet_controllers = @(Get-NetworkInfo)
            hard_drives = @(Get-StorageInfo)
            memory_banks = @(Get-MemoryInfo)
        }

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
                manufacturer = $systemInfo.basicInfo.Manufacturer
                mgt_ip_address = $systemInfo.basicInfo.mgt_ip_address
                mgt_mac_address = $systemInfo.basicInfo.mgt_mac_address
                name_model = $systemInfo.basicInfo.Model
                pools = @("Certification")
                serial_number = $systemInfo.basicInfo.Serial_Number
                sku = "SKU=0000;ModelName=$($systemInfo.Model)"
                uuid = $systemInfo.basicInfo.UUID
                version = "Not Specified"
                inventory_id = $null
                bmc = @{
                    firmware_version = $null
                    guid = $null
                    ip_address = $null
                    mac_address = $null
                    manufacturer = $null
                    vlan = 0
                    user = $null
                    password = $null
                }
                bios = Get-BiosInfo
                cpus = @(Get-ProcessorInfo)
                memory_banks = @(Get-MemoryInfo)
                motherboard = Get-MotherboardInfo
                hard_drives = @(Get-StorageInfo)
                ethernet_controllers = @(Get-NetworkInfo)
                
            }
            schema_metadata = @{
                schema_version = "v0.1"
                origin = "Andreys-Inventory Tool"
            }
        }

        return $inventory
    }
    catch {
        Write-Error "Error getting system inventory: $_"
        return $null
    }
}