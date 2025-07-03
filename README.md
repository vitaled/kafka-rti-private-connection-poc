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

### 3. Access the VM

The VM is automatically configured with Docker and required tools via cloud-init:

```bash
# SSH into the VM using the generated key
ssh -i kafka-vm-key.pem azureuser@<VM_PUBLIC_IP>

# Check setup status
sudo cloud-init status

# View setup logs if needed
sudo cat /var/log/cloud-init-output.log
```

### 4. Start Kafka and Kafka Connect

```bash
# Navigate to project directory
cd kafka-rti-private-connection-poc

# Start the services
docker-compose -f docker/docker-compose.yml up -d

# Verify services are running
docker-compose -f docker/docker-compose.yml ps

# Check Kafka Connect is ready
curl http://localhost:8083/connectors
```

### 5 Configure Kafka Connect Sink Connector

Create a configuration file for the Kafka Connect sink connector:

```json
{
  "name": "kusto-sink-connector",
  "config": {
    "connector.class": "com.microsoft.azure.kusto.kafka.connect.sink.KustoSinkConnector",
    "tasks.max": "1",
    "topics": "test-topic",
    "kusto.ingestion.url": "https://ingest-<ID>.kusto.fabric.microsoft.com", // Replace <ID> with your Kusto cluster ID
    "kusto.query.url": "https://<id>.kusto.fabric.microsoft.com", // Replace <ID> with your Kusto cluster ID
    "aad.auth.authority": "<TENANT_ID>", // Replace with your Azure AD tenant ID
    "aad.auth.appid": "<Client ID>", // Replace with your Application ID
    "aad.auth.appkey": "<Client Secret>", // Replace with your app key
    "kusto.database": "<Kusto Database Name>", // Replace with your Kusto database name
    "kusto.table": "<Kusto Table Name>", // Specify the Kusto table to write to
    "kusto.tables.topics.mapping": "[{'topic': 'test-topic','db': 'kafka','table': 'test','format': 'csv','mapping':'test_mapping','streaming': true}]",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter.schemas.enable": "false"
  }
}
```

Save this as `config/kusto-connector-sink.json`.

### Install the Kusto Sink Connector

To install the Kusto Sink Connector: you can either [download](https://github.com/Azure/kafka-sink-azure-kusto?tab=readme-ov-file#91-download-a-ready-to-use-uber-jar-from-our-github-repo-releases-listing) the JAR file from the [kafka-sink-azure-kusto repository](https://github.com/Azure/kafka-sink-azure-kusto)) or [build](https://github.com/Azure/kafka-sink-azure-kusto?tab=readme-ov-file#93-build-uber-jar-from-source) it from source.

Place the JAR file in the `connectors/` directory and restart docker-compose:

```bash
docker-compose -f docker/docker-compose.yml down
docker-compose -f docker/docker-compose.yml up -d
```

### 6. Register the Connector

Then execute the following command to register the connector:

```bash
curl -X POST http://127.0.0.1:8083/connectors -H 'Content-Type: application/json' -d @config/kusto-connector-sink.json
```

### 7. Send Test Data

To test the connector, produce some sample data to the Kafka topic:

```bash
# Produce test messages to the Kafka topic
docker exec -it kafka-kafka-1 kafka-console-producer --broker-list localhost:9092 --topic test-topic --property "parse.key=true" --property "key.separator=:" <<EOF
1,value1
2,value2
3,value3
```

### 8. Verify Data Flow

Check that data is flowing from Kafka to your KQL database:

```kql
// Query your KQL table in Fabric RTI
YourTargetTable
| take 10
| order by ingestion_time() desc
```

## Performance Tuning

### Connector Optimization

- Adjust `batch.size` based on throughput requirements
- Configure appropriate `tasks.max` for parallelism
- Tune `flush.timeout.ms` for latency vs. throughput balance

### Kafka Connect Cluster

- Allocate sufficient memory and CPU resources
- Monitor JVM heap usage and garbage collection
- Scale horizontally by adding more worker nodes

## Contributing

Contributions are welcome!

## Support

For questions and support:

- 📧 Email: [dvitale@microsoft.com]
- 💬 Issues: [GitHub Issues](https://github.com/vitaled/kafka-rti-private-connection-poc/issues)

### Acknowledgments

- Microsoft Fabric team for Real Time Intelligence platform
- Apache Kafka community
- Confluent for Kafka Connect framework

---

**Note**: This is a proof of concept and should be thoroughly tested before production use. Microsoft Fabric's Real Time Intelligence is continuously evolving, and native private connectivity features may be added in future releases.
