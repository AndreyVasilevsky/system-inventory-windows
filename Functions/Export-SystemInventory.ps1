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

        # Create filename using ONLY the management MAC address
        $macAddress = $inventory.system.mgt_mac_address
        
        # Ensure we have a single valid MAC address
        if ([string]::IsNullOrEmpty($macAddress)) {
            $basicInfo = Get-SystemBasicInfo
            $macAddress = $basicInfo.mgt_mac_address
        }
        
        # Handle case where we might have multiple MACs
        if ($macAddress -match ' ' -or $macAddress -match ',') {
            $macAddress = ($macAddress -split ' |,')[0].Trim()
        }
        
        # Clean MAC format (remove any spaces, colons, etc.)
        $macAddress = $macAddress -replace '[^a-zA-Z0-9]', '-'
        
        # Final safety check
        if ([string]::IsNullOrEmpty($macAddress) -or $macAddress -eq "--") {
            $macAddress = "unknown-" + [Guid]::NewGuid().ToString().Substring(0, 8)
        }

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