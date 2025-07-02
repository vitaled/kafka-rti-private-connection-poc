param(
    [string]$KafkaConnectUrl = "http://localhost:8083",
    [string]$ConfigFile = "kusto-connector/kusto-connector-sink.json",
    [string]$KustoIngestionUrl = "",
    [string]$KustoQueryUrl = "",
    [string]$TenantId = "",
    [string]$ClientId = "",
    [string]$ClientSecret = "",
    [string]$DatabaseName = "",
    [string]$TableName = "",
    [string]$TopicName = "test-topic",
    [string]$MappingName = "test_mapping"
)

Write-Host "🔧 Setting up Kafka Connect Kusto Sink Connector..." -ForegroundColor Green
Write-Host ""

# Check if config file exists
if (-not (Test-Path $ConfigFile)) {
    Write-Host "❌ Configuration file not found: $ConfigFile" -ForegroundColor Red
    exit 1
}

# Read and parse the JSON configuration
try {
    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
}
catch {
    Write-Host "❌ Failed to parse configuration file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Replace placeholders with actual values if provided
if ($KustoIngestionUrl) {
    $config.config.'kusto.ingestion.url' = $KustoIngestionUrl
}
if ($KustoQueryUrl) {
    $config.config.'kusto.query.url' = $KustoQueryUrl
}
if ($TenantId) {
    $config.config.'aad.auth.authority' = $TenantId
}
if ($ClientId) {
    $config.config.'aad.auth.appid' = $ClientId
}
if ($ClientSecret) {
    $config.config.'aad.auth.appkey' = $ClientSecret
}
if ($DatabaseName) {
    $config.config.'kusto.database' = $DatabaseName
}
if ($TableName) {
    $config.config.'kusto.table' = $TableName
}
if ($TopicName) {
    $config.config.topics = $TopicName
}

# Update mapping if values are provided
if ($TopicName -and $DatabaseName -and $TableName -and $MappingName) {
    $mapping = "[{'topic': '$TopicName','db': '$DatabaseName','table': '$TableName','format': 'csv','mapping':'$MappingName','streaming': true}]"
    $config.config.'kusto.tables.topics.mapping' = $mapping
}

# Check if Kafka Connect is running
Write-Host "📡 Checking Kafka Connect status..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$KafkaConnectUrl/connectors" -Method Get -TimeoutSec 10
    Write-Host "✅ Kafka Connect is running. Current connectors: $($response.Count)" -ForegroundColor Green
}
catch {
    Write-Host "❌ Cannot connect to Kafka Connect at $KafkaConnectUrl" -ForegroundColor Red
    Write-Host "Make sure Kafka Connect is running and accessible." -ForegroundColor Yellow
    exit 1
}

# Deploy the connector
Write-Host "🚀 Deploying Kusto Sink Connector..." -ForegroundColor Yellow
try {
    $jsonBody = $config | ConvertTo-Json -Depth 10
    $response = Invoke-RestMethod -Uri "$KafkaConnectUrl/connectors" `
        -Method Post `
        -Body $jsonBody `
        -ContentType "application/json" `
        -TimeoutSec 30

    Write-Host "✅ Connector deployed successfully!" -ForegroundColor Green
    Write-Host "Connector Name: $($response.name)" -ForegroundColor White
    Write-Host "Connector Class: $($response.config.'connector.class')" -ForegroundColor White
}
catch {
    if ($_.Exception.Response.StatusCode -eq 409) {
        Write-Host "⚠️  Connector already exists. Updating configuration..." -ForegroundColor Yellow
        try {
            $updateResponse = Invoke-RestMethod -Uri "$KafkaConnectUrl/connectors/$($config.name)/config" `
                -Method Put `
                -Body ($config.config | ConvertTo-Json -Depth 10) `
                -ContentType "application/json" `
                -TimeoutSec 30
            Write-Host "✅ Connector configuration updated successfully!" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Failed to update connector: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "❌ Failed to deploy connector: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Check connector status
Write-Host "📊 Checking connector status..." -ForegroundColor Yellow
try {
    $status = Invoke-RestMethod -Uri "$KafkaConnectUrl/connectors/$($config.name)/status" -Method Get
    Write-Host "Connector State: $($status.connector.state)" -ForegroundColor White
    
    if ($status.tasks) {
        foreach ($task in $status.tasks) {
            Write-Host "Task $($task.id): $($task.state)" -ForegroundColor White
        }
    }
    
    if ($status.connector.state -eq "RUNNING") {
        Write-Host "✅ Connector is running successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️  Connector state: $($status.connector.state)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "⚠️  Could not check connector status: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🔄 Next Steps:" -ForegroundColor Cyan
Write-Host "1. Send test data to topic: $TopicName" -ForegroundColor White
Write-Host "2. Check data in Kusto table: $TableName" -ForegroundColor White
Write-Host "3. Monitor connector status: $KafkaConnectUrl/connectors/$($config.name)/status" -ForegroundColor White
