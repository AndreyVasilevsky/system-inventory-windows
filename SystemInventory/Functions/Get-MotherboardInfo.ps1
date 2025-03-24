# File: SystemInventory/Functions/Get-MotherboardInfo.ps1
function Get-MotherboardInfo {
    [CmdletBinding()]
    param()
    
    try {
        $baseBoard = Get-WmiObject -Class Win32_BaseBoard
        
        @{
            motherboard_id = $null
            product = $baseBoard.Product
            serial_number = $baseBoard.SerialNumber
            vendor = $baseBoard.Manufacturer
            version = $baseBoard.Version
            cpu_numa_count = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfNumaNodes
            cpu_sockets_count = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfProcessors

        }
    }
    catch {
        Write-Error "Error getting motherboard info: $_"
        return $null
    }
}