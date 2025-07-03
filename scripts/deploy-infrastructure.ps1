param(
    [string]$SubscriptionId = "",
    [string]$ResourceGroupName = "rg-kafka-rti-poc-42",
    [string]$Location = "North Europe"
)

# Configuration
$DeploymentName = "kafka-rti-poc-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$SshKeyName = "kafka-vm-ssh-key"

Write-Host "🚀 Deploying Kafka RTI PoC Infrastructure..." -ForegroundColor Green
Write-Host "Subscription: $(if($SubscriptionId) {$SubscriptionId} else {'Current'})" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Cyan
Write-Host "Location: $Location" -ForegroundColor Cyan
Write-Host ""

# Check if logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        throw "Not logged in"
    }
    if ($SubscriptionId -and $context.Subscription.Id -ne $SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId
    }
}
catch {
    Write-Host "❌ Not logged in to Azure. Please run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}

# Check if Azure CLI is available
try {
    $azVersion = az version --output json | ConvertFrom-Json
    Write-Host "Using Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Blue
}
catch {
    Write-Host "❌ Azure CLI not found. Please install Azure CLI." -ForegroundColor Red
    exit 1
}

# Check if parameters file exists, create from example if not
$parametersPath = "infrastructure/bicep/parameters.json"
$exampleParametersPath = "infrastructure/bicep/parameters.example.json"

if (-not (Test-Path $parametersPath)) {
    Write-Host "📝 Parameters file not found. Creating from example..." -ForegroundColor Yellow
    Copy-Item $exampleParametersPath $parametersPath
    Write-Host "✅ Parameters file created. Using default values." -ForegroundColor Green
}

# Create resource group
Write-Host "📦 Creating resource group..." -ForegroundColor Yellow
try {
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{
        Environment = "POC"
        Project = "Kafka-RTI-Private-Connection"
    } -Force | Out-Null
    Write-Host "✅ Resource group created successfully." -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to create resource group: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create SSH key using Azure CLI
Write-Host "🔑 Creating SSH key..." -ForegroundColor Yellow
try {
    $sshKeyOutput = az sshkey create --name $SshKeyName --resource-group $ResourceGroupName --location $Location --tags Environment=POC Project=Kafka-RTI-Private-Connection 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ SSH key created successfully." -ForegroundColor Green
        
        # Parse the output to extract file paths
        Write-Host "🔑 Processing SSH key output..." -ForegroundColor Yellow
        $privateKeyPath = ""
        $publicKeyPath = ""
        #Printing output for debugging
        Write-Host $sshKeyOutput -ForegroundColor White

        $regex  = [regex]'Private key is saved to "([^"]+)"'
        $match  = $regex.Match(($sshKeyOutput -join "`n"))

        if ($match.Success) {
            $privateKeyPath = $match.Groups[1].Value
            Write-Host "Private key file location: $privateKeyPath" -ForegroundColor Cyan
        } else {
            Write-Error "❌ Pattern not found in SSH-key output."
        }

        # Extract public key path using regex
        $regexPublic = [regex]'Public key is saved to "([^"]+)"'
        $matchPublic = $regexPublic.Match(($sshKeyOutput -join "`n"))

        if ($matchPublic.Success) {
            $publicKeyPath = $matchPublic.Groups[1].Value
            Write-Host "Public key file location: $publicKeyPath" -ForegroundColor Cyan
        } else {
            Write-Error "❌ Pattern not found in SSH-key output."
        }

        # Copy private key to local directory if found
        if ($privateKeyPath -and (Test-Path $privateKeyPath)) {
            Write-Host "🔑 Copying private key to kafka-vm-key.pem..." -ForegroundColor Yellow
            Copy-Item $privateKeyPath "kafka-vm-key.pem"
            Write-Host "✅ Private key saved to kafka-vm-key.pem" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️  Could not find private key file at: $privateKeyPath" -ForegroundColor Yellow
        }
        
        # Copy public key to local directory if found
        if ($publicKeyPath -and (Test-Path $publicKeyPath)) {
            Write-Host "🔑 Copying public key to kafka-vm-key.pub..." -ForegroundColor Yellow
            Copy-Item $publicKeyPath "kafka-vm-key.pub"
        }
        
        # Get the public key from Azure resource as backup
        $sshPublicKey = az sshkey show --name $SshKeyName --resource-group $ResourceGroupName --query publicKey --output tsv
        if (-not (Test-Path "kafka-vm-key.pub")) {
            $sshPublicKey | Out-File -FilePath "kafka-vm-key.pub" -Encoding ASCII -NoNewline
        }
        
        Write-Host "✅ SSH key files created locally." -ForegroundColor Green
        Write-Host "📁 Local SSH key files:" -ForegroundColor Cyan
        Write-Host "  Private key: kafka-vm-key.pem" -ForegroundColor White
        Write-Host "  Public key:  kafka-vm-key.pub" -ForegroundColor White
    }
    else {
        # Check if key already exists
        if ($sshKeyOutput -like "*already exists*") {
            Write-Host "ℹ️  SSH key already exists. Using existing key..." -ForegroundColor Blue
            
            # Get the public key from existing resource
            $sshPublicKey = az sshkey show --name $SshKeyName --resource-group $ResourceGroupName --query publicKey --output tsv
            $sshPublicKey | Out-File -FilePath "kafka-vm-key.pub" -Encoding ASCII -NoNewline
            
            Write-Host "⚠️  Private key not available for existing SSH key resource." -ForegroundColor Yellow
            Write-Host "    If you need the private key, delete the existing key and re-run this script." -ForegroundColor Yellow
        }
        else {
            throw "Failed to create SSH key: $sshKeyOutput"
        }
    }
}
catch {
    Write-Host "❌ Failed to create SSH key: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Validate Bicep template
Write-Host "✅ Validating Bicep template..." -ForegroundColor Yellow
try {
    Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
        -TemplateFile "infrastructure/bicep/main.bicep" `
        -TemplateParameterFile $parametersPath `
        -sshPublicKey $sshPublicKey | Out-Null
    Write-Host "✅ Bicep template validation passed." -ForegroundColor Green
}
catch {
    Write-Host "❌ Bicep template validation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Deploy the template
Write-Host "🚀 Deploying infrastructure..." -ForegroundColor Yellow
try {
    $deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
        -Name $DeploymentName `
        -TemplateFile "infrastructure/bicep/main.bicep" `
        -TemplateParameterFile $parametersPath `
        -sshPublicKey $sshPublicKey

    if ($deployment.ProvisioningState -eq "Succeeded") {
        Write-Host "✅ Infrastructure deployed successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "📋 Deployment Outputs:" -ForegroundColor Cyan
        Write-Host "=====================" -ForegroundColor Cyan
        
        # Get deployment outputs
        $vmPublicIP = $deployment.Outputs.vmPublicIP.Value
        $sshCommand = $deployment.Outputs.sshConnectionCommand.Value
        $kafkaUIUrl = $deployment.Outputs.kafkaUIUrl.Value
        $kafkaConnectUrl = $deployment.Outputs.kafkaConnectUrl.Value
        
        Write-Host "VM Public IP: $vmPublicIP" -ForegroundColor White
        Write-Host "SSH Command: $sshCommand" -ForegroundColor White
        Write-Host "SSH Private Key: kafka-vm-key.pem" -ForegroundColor White
        Write-Host "SSH Public Key: kafka-vm-key.pub" -ForegroundColor White
        Write-Host "Kafka UI: $kafkaUIUrl" -ForegroundColor White
        Write-Host "Kafka Connect: $kafkaConnectUrl" -ForegroundColor White
        Write-Host ""
        Write-Host "🔐 SSH Key Files:" -ForegroundColor Cyan
        if ((Test-Path "kafka-vm-key.pem") -and (Get-Item "kafka-vm-key.pem").Length -gt 0) {
            Write-Host "  Private Key: kafka-vm-key.pem ✅" -ForegroundColor White
        }
        else {
            Write-Host "  Private Key: Not available (use existing key or recreate) ⚠️" -ForegroundColor White
        }
        Write-Host "  Public Key:  kafka-vm-key.pub ✅" -ForegroundColor White
        Write-Host ""
        Write-Host "🔄 Next Steps:" -ForegroundColor Cyan
        Write-Host "1. Wait for VM setup to complete (check cloud-init logs)" -ForegroundColor White
        Write-Host "2. SSH into the VM: $sshCommand" -ForegroundColor White
        Write-Host "3. Start Kafka services: cd kafka-rti-private-connection-poc && docker-compose -f docker/docker-compose.yml up -d" -ForegroundColor White
        Write-Host "4. Create service principal: .\scripts\create-service-principal.ps1" -ForegroundColor White
        Write-Host ""
        Write-Host "⚠️  Keep the kafka-vm-key.pem file secure and do not commit it to version control!" -ForegroundColor Yellow
    }
    else {
        throw "Deployment failed with state: $($deployment.ProvisioningState)"
    }
}
catch {
    Write-Host "❌ Infrastructure deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}