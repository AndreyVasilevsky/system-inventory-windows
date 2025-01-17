# File: SystemInventory/SystemInventory.psm1
# Get the directory where the module is installed
$ModulePath = $PSScriptRoot

# Import all function files from the Functions directory
$FunctionsPath = Join-Path -Path $ModulePath -ChildPath 'Functions'
Write-Verbose "Loading functions from: $FunctionsPath"

# Get all ps1 files from the Functions directory
$FunctionFiles = Get-ChildItem -Path $FunctionsPath -Filter '*.ps1' -ErrorAction SilentlyContinue

# Import each function file
foreach ($FunctionFile in $FunctionFiles) {
    try {
        Write-Verbose "Importing function file: $($FunctionFile.FullName)"
        . $FunctionFile.FullName
    }
    catch {
        Write-Error "Failed to import function file $($FunctionFile.FullName): $_"
    }
}