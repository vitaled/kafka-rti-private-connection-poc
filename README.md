# Kafka-RTI Private Connection Proof of Concept

## Overview

This repository demonstrates a workaround solution for connecting Apache Kafka instances running in private networks to Microsoft Fabric's Real Time Intelligence (RTI) platform. Due to the current lack of native private connectivity for Kafka sources in Real Time Intelligence, this proof of concept showcases how to use Kafka Connect with a Kafka Sink Connector to push data from a private Kafka cluster to a KQL database in RTI.

## Problem Statement

Microsoft Fabric's Real Time Intelligence currently doesn't support direct private connectivity to Kafka clusters running in private networks (VNets, on-premises, or other isolated environments). This limitation prevents organizations from streaming data from their secure Kafka deployments to Fabric RTI without exposing their Kafka clusters to the public internet.

## Solution Architecture

This POC implements a bridge solution using Kafka Connect with a custom sink connector that:

1. **Connects to private Kafka cluster** - Runs within the same private network as your Kafka deployment
2. **Authenticates with Fabric RTI** - Uses Azure AD/Entra ID authentication to securely connect to Fabric
3. **Streams data to KQL Database** - Pushes messages from Kafka topics directly to KQL tables in Real Time Intelligence

### Architecture Diagram

```
┌─────────────────────────────────────────┐
│           Private Network               │
│  ┌─────────────┐    ┌─────────────────┐ │
│  │    Kafka    │    │  Kafka Connect  │ │
│  │   Cluster   |--> │   + Sink        │ │
│  │             │    │   Connector     │ │
│  └─────────────┘    └─────────────────┘ │
└─────────────────────────┼───────────────┘
                          │
                          │ HTTPS/Auth
                          ▼
┌─────────────────────────────────────────┐
│         Microsoft Fabric                │
│  ┌────────────────────────────────────┐ │
│  │     Real Time Intelligence         │ │
│  │    ┌────────────────────────────┐  │ │
│  │    │       KQL Database         │  │ │
│  │    │                            │  │ │
│  │    └────────────────────────────┘  │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

## Features

- ✅ **Private Network Support** - Kafka Connect runs within your private network
- ✅ **Secure Authentication** - Uses Azure AD/Entra ID service principal authentication
- ✅ **Real-time Streaming** - Low-latency data ingestion to KQL databases
- ✅ **Schema Evolution** - Handles schema changes and data type mappings
- ✅ **Error Handling** - Robust error handling and retry mechanisms
- ✅ **Monitoring** - Integration with Kafka Connect monitoring and logging

## Prerequisites

### Azure Subscription

- Active Azure subscription with appropriate permissions
- Azure CLI installed locally
- Bicep CLI installed (or latest Azure CLI with Bicep support)

### Kafka Environment

- Apache Kafka cluster (2.8+ recommended) - Will be deployed via Docker
- Kafka Connect cluster with sufficient resources - Will be deployed via Docker
- Network connectivity between Kafka Connect and Kafka brokers

### Microsoft Fabric

- Microsoft Fabric workspace with Real Time Intelligence enabled
- KQL Database created in RTI
- Azure AD/Entra ID service principal with appropriate permissions

### Authentication Requirements

- Service principal with the following permissions:
  - `Contributor` role on the Fabric workspace
  - `Database Admin` permissions on the target KQL database

## Infrastructure Setup

### 1. Deploy Azure Infrastructure

First, deploy the Azure virtual network and VM using Bicep:

**Windows (PowerShell):**

```powershell
# Clone the repository
git clone https://github.com/vitaled/kafka-rti-private-connection-poc.git
cd kafka-rti-private-connection-poc

# Login to Azure
Connect-AzAccount

# Run the deployment script
.\scripts\deploy-infrastructure.ps1
```

The script will:

- **Generate an SSH key pair automatically** during deployment
- Deploy the Bicep template with all required infrastructure
- **Save the SSH private key as `kafka-vm-key.pem`** in the current directory
- Display connection information

**Important**: The deployment automatically generates a new SSH key pair. The private key is saved as `kafka-vm-key.pem` with proper permissions (chmod 600). Keep this file secure and do not commit it to version control.

### 2. Create Service Principal

Create an Azure service principal for Fabric authentication:

**Windows (PowerShell):**

```powershell
# Run the script
.\scripts\create-service-principal.ps1
```

Save the output credentials securely - you'll need them for the connector configuration.

### 3. Configure Microsoft Fabric Workspace

Before connecting Kafka to your RTI environment, you need to set up the Fabric workspace and KQL database components:

#### 3.1 Create KQL Database

1. Navigate to your **Microsoft Fabric workspace** in the Fabric portal
2. Click **+ New** and select **KQL Database**
3. Provide a name for your database (e.g., `kafka-rti-database`)
4. Click **Create**

#### 3.2 Create Target Table

Once your KQL database is created, create a table to receive the Kafka data:

1. Open your KQL database
2. Click **+ New** and select **KQL Queryset**
3. Execute the following KQL command to create your target table:

```kql
.create table TestTable (
    id: int,
    value: string
)
```

#### 3.3 Create Data Mapping

Create a mapping to define how incoming CSV data should be parsed:

```kql
.create table TestTable ingestion csv mapping 'test_mapping' 
'[{"Name":"id","DataType":"int","Ordinal":0},{"Name":"value","DataType":"string","Ordinal":1}]'
```

#### 3.4 Configure Service Principal Permissions

You need to grant your service principal the necessary permissions to access the workspace and database:

**Add Service Principal as Workspace Contributor:**

1. In your Fabric workspace, click **Workspace settings** (gear icon)
2. Select **Manage access**
3. Click **+ Add people or groups**
4. Search for your service principal by **Application ID** or **Display Name**
5. Select the service principal and assign the **Contributor** role
6. Click **Add**

**Add Service Principal as Database Admin:**

1. In your KQL database, click **Manage** → **Permissions**
2. Click **+ Add**
3. Select **Database Admin**
4. Search for your service principal by **Application ID** or **Display Name**
5. Select the service principal and click **Add**

#### 3.5 Get Database Connection Information

You'll need the following information for your Kafka connector configuration:

1. **Cluster URI**: In your KQL database, go to **Overview** and copy the **Query URI**
   - Format: `https://<cluster-id>.kusto.fabric.microsoft.com`
2. **Ingestion URI**: Replace the query URI domain with the ingestion endpoint
   - Format: `https://ingest-<cluster-id>.kusto.fabric.microsoft.com`
3. **Database Name**: Your KQL database name
4. **Table Name**: `TestTable` (or your custom table name)

**Example Configuration Values:**
```json
{
  "kusto.ingestion.url": "https://ingest-mycluster.kusto.fabric.microsoft.com",
  "kusto.query.url": "https://mycluster.kusto.fabric.microsoft.com",
  "kusto.database": "kafka-rti-database",
  "kusto.table": "TestTable"
}
```

#### 3.6 Test Database Access

Verify that your service principal has the correct permissions by testing a simple query:

```kql
// Test query to verify access
TestTable
| count
```

If you encounter permission errors, double-check that:
- The service principal has **Contributor** role on the workspace
- The service principal has **Database Admin** permissions on the KQL database
- The service principal credentials are correctly configured

### 4. Access the VM

After the infrastructure deployment is complete, you can access the Kafka Connect VM using SSH:

```powershell
# Connect to the VM (replace with your public IP)
ssh -i kafka-vm-key.pem azureuser@<public-ip>

# Example
ssh -i kafka-vm-key.pem azureuser@20.123.456.789
```

**Note**: The default username is `azureuser`. The SSH private key file (`kafka-vm-key.pem`) must have proper permissions (chmod 600).

### 5. Configure and Start Kafka Connect

Once connected to the VM, configure and start the Kafka Connect service:

#### 5.1 Edit Kafka Connect Configuration

Open the Kafka Connect configuration file in a text editor:

```bash
sudo nano /etc/kafka/connect-distributed.properties
```

Update the following properties:

```properties
# Kafka broker address
bootstrap.servers=<kafka-broker-ip>:9092

# Unique group ID for Kafka Connect
group.id=connect-cluster

# Offset storage settings
offset.storage.file.filename=/var/lib/kafka/connect.offsets

# Key and value converter settings
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
value.converter.schemas.enable=false
```

**Note**: Replace `<kafka-broker-ip>` with the actual IP address of your Kafka broker.

#### 5.2 Create Connectors Configuration

Create a new file for your connector configuration:

```bash
sudo nano /etc/kafka/connectors/my-kafka-sink-connector.json
```

Add the following configuration:

```json
{
  "name": "my-kafka-sink-connector",
  "config": {
    "connector.class": "com.microsoft.azure.kusto.kafka.connect.sink.KustoSinkConnector",
    "tasks.max": "1",
    "topics": "test-topic",
    "kusto.cluster": "<cluster-id>.kusto.fabric.microsoft.com",
    "kusto.database": "kafka-rti-database",
    "kusto.table": "TestTable",
    "kusto.ingestion.url": "https://ingest-<cluster-id>.kusto.fabric.microsoft.com",
    "kusto.query.url": "https://<cluster-id>.kusto.fabric.microsoft.com",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "flush.size": "100",
    "linger.ms": "500",
    "retry.backoff.ms": "300",
    "max.in.flight.requests.per.connection": "1",
    "authentication.type": "ServicePrincipal",
    "service.principal": "<app-id>",
    "service.principal.secret": "<app-secret>",
    "tenant.id": "<tenant-id>"
  }
}
```

**Note**: Replace the placeholder values with your actual configuration values.

#### 5.3 Start Kafka Connect Service

Start or restart the Kafka Connect service to apply the changes:

```bash
sudo systemctl restart kafka-connect
```

#### 5.4 Verify Connector Status

Check the status of your connector to ensure it's running correctly:

```bash
curl -X GET http://localhost:8083/connectors/my-kafka-sink-connector/status
```

You should see a response indicating the connector is running and the task is active.

## Testing the Setup

To test the end-to-end setup, produce some test messages to the Kafka topic and verify they appear in the KQL table:

### 1. Produce Test Messages to Kafka

Use the Kafka console producer to send test messages:

```bash
# Open a new terminal and SSH into the Kafka Connect VM

# Produce test messages to the Kafka topic
kafka-console-producer --broker-list <kafka-broker-ip>:9092 --topic test-topic --property "parse.key=true" --property "key.separator=:" <<EOF
1:TestValue1
2:TestValue2
3:TestValue3
EOF
```

### 2. Query the KQL Table

After producing the test messages, query the KQL table to verify the data was ingested:

```kql
// Query the KQL table
TestTable
| order by id asc
```

You should see the test messages appear in the query results.

## Troubleshooting Tips

- Check the Kafka Connect logs for any error messages or stack traces
- Verify that all network security group (NSG) rules and firewall settings allow the necessary traffic
- Ensure that the service principal credentials are correct and have not expired
- Double-check the configuration values for any typos or incorrect settings
- Use the Kafka and Kusto documentation for additional troubleshooting guidance

## Conclusion

This proof of concept demonstrates a viable solution for connecting Apache Kafka instances in private networks to Microsoft Fabric's Real Time Intelligence platform using Kafka Connect and a custom sink connector. By following the steps outlined in this document, you can securely stream data from your private Kafka clusters to KQL databases in RTI, enabling real-time analytics and insights.

## References

- [Microsoft Fabric Documentation](https://docs.microsoft.com/en-us/fabric/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kafka Connect Documentation](https://docs.confluent.io/platform/current/connect/index.html)
- [Kusto Query Language (KQL) Documentation](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- [Azure AD Service Principals](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)
