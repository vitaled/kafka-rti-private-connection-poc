param(
    [string]$ResourceGroupName = "rg-kafka-rti-poc",
    [switch]$Force
)

Write-Host "🧹 Cleaning up Kafka RTI PoC Infrastructure..." -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Cyan
Write-Host ""

# Check if logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        throw "Not logged in"
    }
}
catch {
    Write-Host "❌ Not logged in to Azure. Please run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}

# Check if resource group exists
try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
}
catch {
    Write-Host "ℹ️  Resource group '$ResourceGroupName' does not exist. Nothing to clean up." -ForegroundColor Blue
    exit 0
}

# Confirm deletion unless Force is specified
if (-not $Force) {
    Write-Host "⚠️  This will delete ALL resources in the resource group: $ResourceGroupName" -ForegroundColor Yellow
    $confirmation = Read-Host "Are you sure you want to continue? (y/N)"
    
    if ($confirmation -ne 'y' -and $confirmation -ne 'Y' -and $confirmation -ne 'yes') {
        Write-Host "❌ Cleanup cancelled." -ForegroundColor Red
        exit 1
    }
}

# Delete resource group
Write-Host "🗑️  Deleting resource group and all resources..." -ForegroundColor Yellow
try {
    Remove-AzResourceGroup -Name $ResourceGroupName -Force -AsJob | Out-Null
    Write-Host "✅ Resource group deletion initiated." -ForegroundColor Green
    Write-Host "ℹ️  Resources are being deleted in the background." -ForegroundColor Blue
    Write-Host "You can check the status in the Azure portal or using Get-AzResourceGroup." -ForegroundColor Blue
}
catch {
    Write-Host "❌ Failed to initiate resource group deletion: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
