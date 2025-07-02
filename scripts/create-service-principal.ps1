param(
    [string]$ServicePrincipalName = "kafka-rti-connector-sp",
    [string]$SubscriptionId = ""
)

Write-Host "Creating service principal for Kafka RTI Connector..." -ForegroundColor Green

# Check if logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        throw "Not logged in"
    }
    
    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        $currentSubscriptionId = $SubscriptionId
    }
    else {
        $currentSubscriptionId = $context.Subscription.Id
    }
    
    Write-Host "Subscription ID: $currentSubscriptionId" -ForegroundColor Cyan
}
catch {
    Write-Host "❌ Not logged in to Azure. Please run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}

try {
    # Create service principal
    Write-Host "Creating service principal..." -ForegroundColor Yellow
    
    $sp = New-AzADServicePrincipal -DisplayName $ServicePrincipalName `
        -Role "Contributor" `
        -Scope "/subscriptions/$currentSubscriptionId"
    
    # Get the service principal details
    $clientId = $sp.AppId
    $tenantId = (Get-AzContext).Tenant.Id
    
    # Get the client secret (password)
    $clientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sp.PasswordCredentials.SecretText))
    
    Write-Host "✅ Service principal created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Service Principal Details:" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Client ID: $clientId" -ForegroundColor White
    Write-Host "Client Secret: $clientSecret" -ForegroundColor White
    Write-Host "Tenant ID: $tenantId" -ForegroundColor White
    Write-Host ""
    Write-Host "⚠️  IMPORTANT: Save these credentials securely!" -ForegroundColor Yellow
    Write-Host "The client secret cannot be retrieved again." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "🔧 Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Add the service principal to your Fabric workspace with Contributor role" -ForegroundColor White
    Write-Host "2. Grant Database Admin permissions on your KQL database" -ForegroundColor White
    Write-Host "3. Update your connector configuration with these credentials" -ForegroundColor White
    
    # Save to file
    $credentials = @{
        clientId = $clientId
        clientSecret = $clientSecret
        tenantId = $tenantId
    }
    
    $credentials | ConvertTo-Json -Depth 3 | Out-File -FilePath "service-principal-credentials.json" -Encoding UTF8
    Write-Host "💾 Credentials saved to: service-principal-credentials.json" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to create service principal: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
