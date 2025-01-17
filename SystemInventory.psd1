# File: SystemInventory/SystemInventory.psd1
@{
    RootModule = 'SystemInventory.psm1'
    ModuleVersion = '1.0.0'
    GUID = '12345678-1234-1234-1774-123333389012'  # Generate a new GUID for your module
    Author = 'Your Name'
    Description = 'System Inventory Collection Module'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-SystemInventory'
        'Get-SystemBasicInfo'
        'Get-BiosInfo'
        'Get-MotherboardInfo'
        'Get-ProcessorInfo'
        'Get-NetworkInfo'
        'Get-StorageInfo'
        'Get-MemoryInfo'
        'Export-SystemInventory'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('System', 'Inventory', 'Hardware')
            ProjectUri = ''
            LicenseUri = ''
        }
    }
}

