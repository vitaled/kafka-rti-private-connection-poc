# SSH Connection Guide

This guide explains how to connect to your Kafka VM using the generated SSH private key (.pem file).

## Overview

When you deploy the infrastructure, the Bicep template automatically:
1. Generates an SSH key pair in Azure
2. Configures the VM with the public key
3. Returns the private key in the deployment output
4. Saves the private key as `kafka-vm-key.pem`

## Connecting to the VM

### Prerequisites
- VM deployed successfully using the Bicep template
- `kafka-vm-key.pem` file in your current directory
- SSH client installed (built-in on Linux/macOS, available on Windows 10+)

### Connection Steps

#### Linux/macOS
```bash
# Ensure correct permissions on the private key
chmod 600 kafka-vm-key.pem

# Connect to the VM
ssh -i kafka-vm-key.pem azureuser@<VM_PUBLIC_IP>

# Example (replace with your actual IP)
ssh -i kafka-vm-key.pem azureuser@20.123.45.67
```

#### Windows (Command Prompt/PowerShell)
```cmd
# Connect to the VM
ssh -i kafka-vm-key.pem azureuser@<VM_PUBLIC_IP>

# Example (replace with your actual IP)
ssh -i kafka-vm-key.pem azureuser@20.123.45.67
```

#### Windows (PuTTY)
If you prefer using PuTTY, you'll need to convert the .pem file to .ppk format:

1. **Install PuTTY** (includes PuTTYgen)
2. **Convert .pem to .ppk**:
   ```
   puttygen kafka-vm-key.pem -o kafka-vm-key.ppk
   ```
3. **Connect using PuTTY**:
   - Host Name: `azureuser@<VM_PUBLIC_IP>`
   - Connection > SSH > Auth > Private key file: Browse to `kafka-vm-key.ppk`
   - Click "Open"

### Getting the VM IP Address

The VM public IP is available in several ways:

#### From Deployment Output
```bash
# Linux/macOS
./scripts/deploy-infrastructure.sh

# Windows PowerShell
.\scripts\deploy-infrastructure.ps1
```

#### From Azure CLI
```bash
az vm show -d -g rg-kafka-rti-poc -n kafka-vm --query publicIps -o tsv
```

#### From Azure PowerShell
```powershell
(Get-AzVM -ResourceGroupName "rg-kafka-rti-poc" -Name "kafka-vm" | Get-AzPublicIpAddress).IpAddress
```

## Troubleshooting

### Permission Denied (publickey)
**Problem**: SSH connection fails with "Permission denied (publickey)"

**Solutions**:
1. **Check file permissions**:
   ```bash
   chmod 600 kafka-vm-key.pem
   ```

2. **Verify the correct private key**:
   ```bash
   ssh -i kafka-vm-key.pem -v azureuser@<VM_IP>
   ```

3. **Check if the key matches**:
   ```bash
   ssh-keygen -y -f kafka-vm-key.pem
   ```

### Connection Timeout
**Problem**: SSH connection times out

**Solutions**:
1. **Check Network Security Group rules**:
   - Ensure SSH (port 22) is allowed
   - Check source IP restrictions

2. **Verify VM is running**:
   ```bash
   az vm get-instance-view -g rg-kafka-rti-poc -n kafka-vm --query instanceView.statuses
   ```

3. **Check public IP**:
   ```bash
   az network public-ip show -g rg-kafka-rti-poc -n kafka-vm-ip --query ipAddress
   ```

### Wrong Username
**Problem**: Login incorrect or permission denied

**Solution**: Use the correct username (default is `azureuser`):
```bash
ssh -i kafka-vm-key.pem azureuser@<VM_IP>
```

### Key File Not Found
**Problem**: SSH can't find the key file

**Solutions**:
1. **Check file exists**:
   ```bash
   ls -la kafka-vm-key.pem
   ```

2. **Use absolute path**:
   ```bash
   ssh -i /full/path/to/kafka-vm-key.pem azureuser@<VM_IP>
   ```

## Security Best Practices

### Protect Your Private Key
- **Never share** the .pem file
- **Never commit** it to version control
- **Set restrictive permissions**: `chmod 600 kafka-vm-key.pem`
- **Store securely** (consider Azure Key Vault for production)

### Network Security
- **Restrict SSH access** to specific IP ranges in NSG rules
- **Use VPN or bastion host** for production environments
- **Monitor SSH logs** for unauthorized access attempts

### Key Rotation
For production environments, regularly rotate SSH keys:

```bash
# Generate new key pair
az sshkey create --name kafka-vm-ssh-key-new --resource-group rg-kafka-rti-poc

# Update VM with new key
az vm user update --username azureuser --ssh-key-value "$(cat new-key.pub)" --resource-group rg-kafka-rti-poc --name kafka-vm

# Remove old key after verification
```

## Advanced SSH Configuration

### SSH Config File
Create `~/.ssh/config` for easier connections:

```
Host kafka-vm
    HostName <VM_PUBLIC_IP>
    User azureuser
    IdentityFile ~/path/to/kafka-vm-key.pem
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

Then connect simply with:
```bash
ssh kafka-vm
```

### Port Forwarding
Forward local ports to access services on the VM:

```bash
# Forward Kafka UI (8080) to local port 8080
ssh -i kafka-vm-key.pem -L 8080:localhost:8080 azureuser@<VM_IP>

# Forward Kafka Connect API (8083) to local port 8083  
ssh -i kafka-vm-key.pem -L 8083:localhost:8083 azureuser@<VM_IP>

# Multiple ports
ssh -i kafka-vm-key.pem -L 8080:localhost:8080 -L 8083:localhost:8083 azureuser@<VM_IP>
```

## Next Steps

Once connected to the VM:

1. **Check setup status**:
   ```bash
   sudo cloud-init status
   ```

2. **Start Kafka services**:
   ```bash
   cd kafka-rti-private-connection-poc
   docker-compose -f docker/docker-compose.yml up -d
   ```

3. **Monitor services**:
   ```bash
   docker-compose -f docker/docker-compose.yml ps
   ```

4. **Access Kafka UI**: Open browser to `http://<VM_IP>:8080`
