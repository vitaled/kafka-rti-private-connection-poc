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
    # Create service principal with shorter credential lifetime
    Write-Host "Creating service principal..." -ForegroundColor Yellow
    
    # First create the application
    $app = New-AzADApplication -DisplayName $ServicePrincipalName
    
    # Create a credential with shorter lifetime (1 year instead of default)
    $startDate = Get-Date
    $endDate = $startDate.AddDays(7)
    
    $credential = New-AzADAppCredential -ApplicationId $app.AppId -StartDate $startDate -EndDate $endDate
    
    # Create the service principal
    $sp = New-AzADServicePrincipal -ApplicationId $app.AppId
    
    # Assign the Contributor role
    New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName "Contributor" -Scope "/subscriptions/$currentSubscriptionId"
    
    # Get the service principal details
    $clientId = $app.AppId
    $tenantId = (Get-AzContext).Tenant.Id
    $clientSecret = $credential.SecretText
    
    Write-Host "✅ Service principal created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Service Principal Details:" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Client ID: $clientId" -ForegroundColor White
    Write-Host "Client Secret: $clientSecret" -ForegroundColor White
    Write-Host "Tenant ID: $tenantId" -ForegroundColor White
    Write-Host "Credential Expires: $($endDate.ToString('yyyy-MM-dd'))" -ForegroundColor White
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
        expiryDate = $endDate.ToString('yyyy-MM-dd')
    }
    
    $credentials | ConvertTo-Json -Depth 3 | Out-File -FilePath "service-principal-credentials.json" -Encoding UTF8
    Write-Host "💾 Credentials saved to: service-principal-credentials.json" -ForegroundColor Green
}
catch {
    if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*DisplayName*") {
        Write-Host "⚠️  Service principal with name '$ServicePrincipalName' may already exist." -ForegroundColor Yellow
        Write-Host "Trying to retrieve existing service principal..." -ForegroundColor Yellow
        
        try {
            # Try to get existing service principal
            $existingSp = Get-AzADServicePrincipal -DisplayName $ServicePrincipalName
            if ($existingSp) {
                Write-Host "✅ Found existing service principal." -ForegroundColor Green
                Write-Host "Client ID: $($existingSp.AppId)" -ForegroundColor White
                Write-Host "Tenant ID: $((Get-AzContext).Tenant.Id)" -ForegroundColor White
                Write-Host ""
                Write-Host "⚠️  Cannot retrieve the client secret for existing service principal." -ForegroundColor Yellow
                Write-Host "If you need a new secret, please:" -ForegroundColor Yellow
                Write-Host "1. Delete the existing service principal: Remove-AzADServicePrincipal -ObjectId $($existingSp.Id)" -ForegroundColor White
                Write-Host "2. Re-run this script" -ForegroundColor White
            }
        }
        catch {
            Write-Host "❌ Failed to retrieve existing service principal: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "❌ Failed to create service principal: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}