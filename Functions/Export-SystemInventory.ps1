# File: SystemInventory/Functions/Export-SystemInventory.ps1
function Export-SystemInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$OutputPath = $PWD
    )
    
    try {
        $inventory = Get-SystemInventory
        if ($null -eq $inventory) {
            throw "Failed to get system inventory"
        }

        # Create filename using MAC address
        $macAddress = $inventory.system.mgt_mac_address -replace ':', '-'
        $fileName = Join-Path $OutputPath "auto_inventory_$macAddress.json"

        # Export to JSON file
        $inventory | ConvertTo-Json -Depth 10 | Out-File $fileName

        Write-Host "Inventory has been saved to $fileName"
        return $fileName
    }
    catch {
        Write-Error "Error exporting system inventory: $_"
        return $null
    }
}