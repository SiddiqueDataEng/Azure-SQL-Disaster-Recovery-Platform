# =====================================================
# Azure SQL Disaster Recovery Platform (ASDRP)
# Create Disaster Recovery Alerts
# Production-Ready Enterprise SQL Disaster Recovery
# =====================================================

<#
.SYNOPSIS
    Creates comprehensive alert rules for Azure SQL Database disaster recovery monitoring.

.DESCRIPTION
    This script creates a complete set of alert rules to monitor the health
    and performance of Azure SQL Database disaster recovery components including
    replication lag, failover events, database availability, and performance metrics.

.PARAMETER ResourceGroupName
    The name of the resource group containing the SQL resources.

.PARAMETER PrimaryServerName
    The name of the primary SQL server.

.PARAMETER SecondaryServerName
    The name of the secondary SQL server.

.PARAMETER DatabaseName
    The name of the database to monitor.

.PARAMETER ActionGroupName
    The name of the action group for alert notifications.

.PARAMETER NotificationEmails
    Array of email addresses for alert notifications.

.PARAMETER WebhookUrl
    Optional webhook URL for alert notifications.

.PARAMETER AlertPrefix
    Prefix for alert rule names (default: "ASDRP").

.EXAMPLE
    .\Create-Disaster-Recovery-Alerts.ps1 -ResourceGroupName "rg-sql-dr" -PrimaryServerName "sql-primary" -SecondaryServerName "sql-secondary" -DatabaseName "ProductionDB" -ActionGroupName "sql-dr-alerts" -NotificationEmails @("admin@company.com", "dba@company.com")
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$PrimaryServerName,
    
    [Parameter(Mandatory = $true)]
    [string]$SecondaryServerName,
    
    [Parameter(Mandatory = $true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory = $true)]
    [string]$ActionGroupName,
    
    [Parameter(Mandatory = $true)]
    [string[]]$NotificationEmails,
    
    [Parameter(Mandatory = $false)]
    [string]$WebhookUrl,
    
    [Parameter(Mandatory = $false)]
    [string]$AlertPrefix = "ASDRP"
)

# Import required modules
Import-Module Az.Monitor -Force
Import-Module Az.Sql -Force
Import-Module Az.Resources -Force

# Set error action preference
$ErrorActionPreference = "Stop"

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Azure SQL Disaster Recovery Platform" -ForegroundColor Cyan
    Write-Host "Create Disaster Recovery Alerts" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $creationStartTime = Get-Date
    
    # Get subscription and resource information
    $subscription = Get-AzContext
    $subscriptionId = $subscription.Subscription.Id
    
    Write-Host "Subscription: $($subscription.Subscription.Name)" -ForegroundColor White
    Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "Primary Server: $PrimaryServerName" -ForegroundColor White
    Write-Host "Secondary Server: $SecondaryServerName" -ForegroundColor White
    Write-Host "Database: $DatabaseName" -ForegroundColor White
    
    # Verify resources exist
    Write-Host "`nVerifying resources..." -ForegroundColor Yellow
    
    $primaryServer = Get-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $PrimaryServerName
    if (-not $primaryServer) {
        throw "Primary server '$PrimaryServerName' not found"
    }
    
    $secondaryServer = Get-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $SecondaryServerName
    if (-not $secondaryServer) {
        throw "Secondary server '$SecondaryServerName' not found"
    }
    
    $database = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $PrimaryServerName -DatabaseName $DatabaseName
    if (-not $database) {
        throw "Database '$DatabaseName' not found"
    }
    
    Write-Host "Resource verification completed." -ForegroundColor Green
    
    # Create or update action group
    Write-Host "`nCreating action group..." -ForegroundColor Yellow
    
    # Prepare email receivers
    $emailReceivers = @()
    foreach ($email in $NotificationEmails) {
        $emailReceivers += New-AzActionGroupReceiver -Name ($email.Split('@')[0]) -EmailReceiver -EmailAddress $email
    }
    
    # Add webhook receiver if provided
    if ($WebhookUrl) {
        $webhookReceiver = New-AzActionGroupReceiver -Name "webhook" -WebhookReceiver -ServiceUri $WebhookUrl
        $allReceivers = $emailReceivers + $webhookReceiver
    }
    else {
        $allReceivers = $emailReceivers
    }
    
    # Create action group
    $actionGroup = Set-AzActionGroup `
        -ResourceGroupName $ResourceGroupName `
        -Name $ActionGroupName `
        -ShortName ($ActionGroupName.Substring(0, [Math]::Min(12, $ActionGroupName.Length))) `
        -Receiver $allReceivers
    
    Write-Host "Action group '$ActionGroupName' created/updated successfully." -ForegroundColor Green
    
    # Define alert rules
    $alertRules = @(
        @{
            Name = "$AlertPrefix-Replication-Lag-High"
            Description = "Alert when replication lag exceeds 5 minutes"
            MetricName = "replication_lag"
            Operator = "GreaterThan"
            Threshold = 300
            TimeAggregation = "Average"
            WindowSize = "PT5M"
            Frequency = "PT1M"
            Severity = 2
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$PrimaryServerName/$DatabaseName"
        },
        @{
            Name = "$AlertPrefix-Replication-Lag-Critical"
            Description = "Critical alert when replication lag exceeds 15 minutes"
            MetricName = "replication_lag"
            Operator = "GreaterThan"
            Threshold = 900
            TimeAggregation = "Average"
            WindowSize = "PT5M"
            Frequency = "PT1M"
            Severity = 0
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$PrimaryServerName/$DatabaseName"
        },
        @{
            Name = "$AlertPrefix-Database-Connection-Failed"
            Description = "Alert when database connection attempts fail"
            MetricName = "connection_failed"
            Operator = "GreaterThan"
            Threshold = 10
            TimeAggregation = "Total"
            WindowSize = "PT5M"
            Frequency = "PT1M"
            Severity = 1
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$PrimaryServerName/$DatabaseName"
        },
        @{
            Name = "$AlertPrefix-Database-DTU-High"
            Description = "Alert when database DTU percentage is high"
            MetricName = "dtu_consumption_percent"
            Operator = "GreaterThan"
            Threshold = 80
            TimeAggregation = "Average"
            WindowSize = "PT15M"
            Frequency = "PT5M"
            Severity = 2
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$PrimaryServerName/$DatabaseName"
        },
        @{
            Name = "$AlertPrefix-Database-CPU-High"
            Description = "Alert when database CPU percentage is high"
            MetricName = "cpu_percent"
            Operator = "GreaterThan"
            Threshold = 85
            TimeAggregation = "Average"
            WindowSize = "PT15M"
            Frequency = "PT5M"
            Severity = 2
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$PrimaryServerName/$DatabaseName"
        },
        @{
            Name = "$AlertPrefix-Database-Storage-High"
            Description = "Alert when database storage usage is high"
            MetricName = "storage_percent"
            Operator = "GreaterThan"
            Threshold = 85
            TimeAggregation = "Average"
            WindowSize = "PT15M"
            Frequency = "PT5M"
            Severity = 2
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$PrimaryServerName/$DatabaseName"
        },
        @{
            Name = "$AlertPrefix-Database-Deadlocks"
            Description = "Alert when database deadlocks occur"
            MetricName = "deadlock"
            Operator = "GreaterThan"
            Threshold = 5
            TimeAggregation = "Total"
            WindowSize = "PT15M"
            Frequency = "PT5M"
            Severity = 2
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$PrimaryServerName/$DatabaseName"
        },
        @{
            Name = "$AlertPrefix-Database-Blocked-Processes"
            Description = "Alert when database has blocked processes"
            MetricName = "blocked_by_firewall"
            Operator = "GreaterThan"
            Threshold = 10
            TimeAggregation = "Total"
            WindowSize = "PT5M"
            Frequency = "PT1M"
            Severity = 1
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$PrimaryServerName/$DatabaseName"
        }
    )
    
    # Create alert rules for secondary database
    $secondaryAlertRules = @(
        @{
            Name = "$AlertPrefix-Secondary-Database-Connection-Failed"
            Description = "Alert when secondary database connection attempts fail"
            MetricName = "connection_failed"
            Operator = "GreaterThan"
            Threshold = 10
            TimeAggregation = "Total"
            WindowSize = "PT5M"
            Frequency = "PT1M"
            Severity = 1
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$SecondaryServerName/$DatabaseName"
        },
        @{
            Name = "$AlertPrefix-Secondary-Database-DTU-High"
            Description = "Alert when secondary database DTU percentage is high"
            MetricName = "dtu_consumption_percent"
            Operator = "GreaterThan"
            Threshold = 80
            TimeAggregation = "Average"
            WindowSize = "PT15M"
            Frequency = "PT5M"
            Severity = 2
            ResourceType = "Microsoft.Sql/servers/databases"
            ResourceName = "$SecondaryServerName/$DatabaseName"
        }
    )
    
    # Combine all alert rules
    $allAlertRules = $alertRules + $secondaryAlertRules
    
    Write-Host "`nCreating alert rules..." -ForegroundColor Yellow
    $createdAlerts = @()
    $failedAlerts = @()
    
    foreach ($rule in $allAlertRules) {
        try {
            Write-Host "Creating alert: $($rule.Name)..." -ForegroundColor White
            
            # Build resource ID
            $resourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/$($rule.ResourceType)/$($rule.ResourceName)"
            
            # Create metric criteria
            $criteria = New-AzMetricAlertRuleV2Criteria `
                -MetricName $rule.MetricName `
                -TimeAggregation $rule.TimeAggregation `
                -Operator $rule.Operator `
                -Threshold $rule.Threshold
            
            # Create action group reference
            $actionGroupId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/actionGroups/$ActionGroupName"
            $actionGroupReference = New-AzActionGroup -ActionGroupId $actionGroupId
            
            # Create alert rule
            $alertRule = Add-AzMetricAlertRuleV2 `
                -Name $rule.Name `
                -ResourceGroupName $ResourceGroupName `
                -WindowSize $rule.WindowSize `
                -Frequency $rule.Frequency `
                -TargetResourceId $resourceId `
                -Condition $criteria `
                -ActionGroup $actionGroupReference `
                -Severity $rule.Severity `
                -Description $rule.Description `
                -Enabled $true
            
            $createdAlerts += $rule.Name
            Write-Host "  ✓ Created successfully" -ForegroundColor Green
        }
        catch {
            $failedAlerts += @{
                Name = $rule.Name
                Error = $_.Exception.Message
            }
            Write-Warning "  ✗ Failed to create: $($_.Exception.Message)"
        }
    }
    
    # Create activity log alerts for failover events
    Write-Host "`nCreating activity log alerts..." -ForegroundColor Yellow
    
    try {
        # Failover event alert
        $failoverCondition = New-AzActivityLogAlertCondition `
            -Field "category" `
            -Equal "Administrative"
        
        $failoverCondition2 = New-AzActivityLogAlertCondition `
            -Field "operationName" `
            -Equal "Microsoft.Sql/servers/databases/failover/action"
        
        $failoverAlert = Set-AzActivityLogAlert `
            -ResourceGroupName $ResourceGroupName `
            -Name "$AlertPrefix-Database-Failover-Event" `
            -Scope "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName" `
            -Condition $failoverCondition, $failoverCondition2 `
            -ActionGroup $actionGroupId `
            -Description "Alert when database failover occurs"
        
        $createdAlerts += "$AlertPrefix-Database-Failover-Event"
        Write-Host "  ✓ Failover event alert created" -ForegroundColor Green
    }
    catch {
        $failedAlerts += @{
            Name = "$AlertPrefix-Database-Failover-Event"
            Error = $_.Exception.Message
        }
        Write-Warning "  ✗ Failed to create failover alert: $($_.Exception.Message)"
    }
    
    $creationEndTime = Get-Date
    $creationDuration = ($creationEndTime - $creationStartTime).TotalSeconds
    
    # Output summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Alert Creation Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "Action Group: $ActionGroupName" -ForegroundColor White
    Write-Host "Alert Prefix: $AlertPrefix" -ForegroundColor White
    Write-Host "Total Alerts Attempted: $($allAlertRules.Count + 1)" -ForegroundColor White
    Write-Host "Successfully Created: $($createdAlerts.Count)" -ForegroundColor Green
    Write-Host "Failed: $($failedAlerts.Count)" -ForegroundColor Red
    Write-Host "Creation Duration: $creationDuration seconds" -ForegroundColor White
    Write-Host "Start Time: $creationStartTime" -ForegroundColor White
    Write-Host "End Time: $creationEndTime" -ForegroundColor White
    
    if ($createdAlerts.Count -gt 0) {
        Write-Host "`nSuccessfully Created Alerts:" -ForegroundColor Green
        foreach ($alert in $createdAlerts) {
            Write-Host "  ✓ $alert" -ForegroundColor Green
        }
    }
    
    if ($failedAlerts.Count -gt 0) {
        Write-Host "`nFailed Alerts:" -ForegroundColor Red
        foreach ($alert in $failedAlerts) {
            Write-Host "  ✗ $($alert.Name): $($alert.Error)" -ForegroundColor Red
        }
    }
    
    Write-Host "`nNotification Recipients:" -ForegroundColor White
    foreach ($email in $NotificationEmails) {
        Write-Host "  📧 $email" -ForegroundColor White
    }
    
    if ($WebhookUrl) {
        Write-Host "  🔗 Webhook: $WebhookUrl" -ForegroundColor White
    }
    
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Important notes
    Write-Host "`nIMPORTANT NOTES:" -ForegroundColor Yellow
    Write-Host "• Monitor alert notifications to ensure they're working correctly" -ForegroundColor White
    Write-Host "• Adjust thresholds based on your specific requirements" -ForegroundColor White
    Write-Host "• Test alert rules by triggering conditions in non-production" -ForegroundColor White
    Write-Host "• Review and update alert rules regularly" -ForegroundColor White
    Write-Host "• Consider adding SMS or voice notifications for critical alerts" -ForegroundColor White
    
    # Return summary
    return @{
        ResourceGroupName = $ResourceGroupName
        ActionGroupName = $ActionGroupName
        AlertPrefix = $AlertPrefix
        TotalAlertsAttempted = $allAlertRules.Count + 1
        SuccessfullyCreated = $createdAlerts.Count
        Failed = $failedAlerts.Count
        CreatedAlerts = $createdAlerts
        FailedAlerts = $failedAlerts
        CreationDuration = $creationDuration
        StartTime = $creationStartTime
        EndTime = $creationEndTime
        Status = if ($failedAlerts.Count -eq 0) { "COMPLETED" } else { "COMPLETED_WITH_ERRORS" }
    }
}
catch {
    Write-Error "Failed to create disaster recovery alerts: $($_.Exception.Message)"
    
    # Log failure details
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Alert Creation Failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "Action Group: $ActionGroupName" -ForegroundColor White
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Time: $(Get-Date)" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Red
    
    throw
}