function Get-SystemBasicInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Subnet
    )
    
    try {
        if (-not $Subnet) {
            $subnetFilePath = Join-Path -Path $PSScriptRoot -ChildPath "subnet.txt"
            if (Test-Path $subnetFilePath) {
                $Subnet = Get-Content -Path $subnetFilePath -ErrorAction Stop
            } else {
                throw "Subnet not provided and subnet.txt file not found."
            }
        }
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        
        # Get first IP in the specified subnet
        $firstIP = Get-NetIPAddress | Where-Object { 
            $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -like "$Subnet*"
        } | Select-Object -First 1
        
        # Get adapter index and MAC based on the first IP
        $adapterIndex = $firstIP.InterfaceIndex
        $macAddress = if ($adapterIndex) {
            (Get-NetAdapter -InterfaceIndex $adapterIndex -ErrorAction SilentlyContinue).MacAddress -replace "-", ":"
        } else { $null }
        
        @{
            system_id = $null
            system_name = $env:COMPUTERNAME
            created_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            description = $null
            manufacturer = $computerSystem.Manufacturer
            mgt_ip_address = $firstIP.IPAddress
            mgt_adapter_index = $adapterIndex
            mgt_mac_address = $macAddress
            name_model = $computerSystem.Model
            serial_number = (Get-WmiObject -Class Win32_BIOS).SerialNumber
            uuid = (Get-WmiObject -Class Win32_ComputerSystemProduct).UUID
        }
    }
    catch {
        Write-Error "Error getting system basic info: $_"
        return $null
    }
}