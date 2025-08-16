# Auto-Shutdown Configuration Guide

This document explains how to configure the auto-shutdown feature for your SOC lab VM.

## Overview

The auto-shutdown feature automatically stops your VM at a specified time every day to help control costs and ensure the lab environment is properly managed.

## Configuration Variables

### `auto_shutdown_enabled` (boolean)
- **Default**: `true`
- **Description**: Enable or disable the auto-shutdown feature
- **Examples**:
  ```hcl
  auto_shutdown_enabled = true   # Enable auto-shutdown
  auto_shutdown_enabled = false  # Disable auto-shutdown
  ```

### `auto_shutdown_time` (string)
- **Default**: `"0700"` (7:00 AM)
- **Description**: Time to shutdown the VM in 24-hour format (HHMM)
- **Examples**:
  ```hcl
  auto_shutdown_time = "0700"  # 7:00 AM
  auto_shutdown_time = "1800"  # 6:00 PM
  auto_shutdown_time = "2300"  # 11:00 PM
  ```

### `auto_shutdown_timezone` (string)
- **Default**: `"UTC"`
- **Description**: Timezone for the shutdown schedule
- **Common Examples**:
  ```hcl
  # US Timezones
  auto_shutdown_timezone = "Eastern Standard Time"
  auto_shutdown_timezone = "Central Standard Time"
  auto_shutdown_timezone = "Mountain Standard Time"
  auto_shutdown_timezone = "Pacific Standard Time"
  
  # Other Common Timezones
  auto_shutdown_timezone = "GMT Standard Time"           # London
  auto_shutdown_timezone = "Central European Time"      # Paris/Berlin
  auto_shutdown_timezone = "Tokyo Standard Time"        # Tokyo
  auto_shutdown_timezone = "AUS Eastern Standard Time"  # Sydney
  auto_shutdown_timezone = "UTC"                        # Universal Time
  ```

### `auto_shutdown_notification_email` (string)
- **Default**: `""` (disabled)
- **Description**: Email address to receive shutdown notifications
- **Examples**:
  ```hcl
  auto_shutdown_notification_email = ""                    # No notifications
  auto_shutdown_notification_email = "admin@company.com"   # Send notifications
  ```

## How It Works

1. **Schedule Creation**: Creates an Azure DevTest Labs schedule resource
2. **Daily Execution**: Runs every day at the specified time
3. **Graceful Shutdown**: Performs a graceful shutdown of the VM
4. **Notifications**: Sends email notification 30 minutes before shutdown (if configured)
5. **Manual Override**: You can manually start the VM anytime after shutdown

## Cost Benefits

Auto-shutdown helps control Azure costs:
- **VM Compute**: Stopped VMs don't incur compute charges
- **Storage**: Disk storage charges continue (minimal cost)
- **Network**: Static IP is retained (small ongoing cost)

**Example Cost Savings:**
- Standard_DS1_v2 VM running 24/7: ~$50/month
- Same VM with 12-hour daily shutdown: ~$25/month
- **Potential savings: 50% on compute costs**

## Usage Examples

### Example 1: Shutdown at 6:00 PM EST with notifications
```hcl
auto_shutdown_enabled            = true
auto_shutdown_time              = "1800"
auto_shutdown_timezone          = "Eastern Standard Time"
auto_shutdown_notification_email = "admin@company.com"
```

### Example 2: Shutdown at 11:00 PM UTC (no notifications)
```hcl
auto_shutdown_enabled            = true
auto_shutdown_time              = "2300"
auto_shutdown_timezone          = "UTC"
auto_shutdown_notification_email = ""
```

### Example 3: Disable auto-shutdown
```hcl
auto_shutdown_enabled = false
```

## Manual VM Management

After auto-shutdown, you can:

### Start VM via Azure CLI
```bash
az vm start --resource-group "your-resource-group" --name "controlNode1"
```

### Start VM via Terraform
```bash
# No specific action needed - Terraform will start VM on next apply if it's defined
terraform apply
```

### Start VM via Azure Portal
1. Go to Azure Portal
2. Navigate to Virtual Machines
3. Select your VM
4. Click "Start"

## Monitoring Auto-Shutdown

### Check Current Configuration
```bash
terraform output auto_shutdown_info
```

### View Azure Activity Logs
- Azure Portal → Activity Log
- Filter by "Stop Virtual Machine" operations
- View shutdown history and any errors

### Check Shutdown Status
```bash
# Check VM power state
az vm get-instance-view --resource-group "your-rg" --name "controlNode1" --query "instanceView.statuses[?code=='PowerState/*'].displayStatus" -o table
```

## Troubleshooting

### VM Doesn't Shutdown
1. Check if auto-shutdown is enabled in Azure Portal
2. Verify timezone configuration
3. Check Activity Log for error messages

### Notification Emails Not Received
1. Verify email address is correct
2. Check spam/junk folder
3. Ensure email notifications are enabled

### Timezone Issues
1. Use exact timezone names from Azure
2. Common mistake: "EST" vs "Eastern Standard Time"
3. Test with UTC first, then adjust

## Best Practices

1. **Set Appropriate Time**: Choose a time when lab usage is minimal
2. **Use Notifications**: Enable email notifications for awareness
3. **Document Schedule**: Inform team members of shutdown schedule
4. **Monitor Costs**: Use Azure Cost Management to track savings
5. **Regular Review**: Periodically review and adjust shutdown time

## Advanced Configuration

### Different Schedules for Different Environments
```hcl
# Development environment - shutdown early
auto_shutdown_time = "1700"  # 5:00 PM

# Testing environment - shutdown late
auto_shutdown_time = "2200"  # 10:00 PM

# Production lab - weekend only shutdown
# (requires custom schedule configuration)
```

### Integration with CI/CD
```bash
# Start VM before running tests
az vm start --resource-group "lab-rg" --name "controlNode1"

# Run your tests
./run-security-tests.sh

# Optional: Stop VM after tests (if not waiting for auto-shutdown)
az vm deallocate --resource-group "lab-rg" --name "controlNode1"
```

This auto-shutdown configuration helps maintain a cost-effective SOC lab while ensuring your resources are properly managed!
