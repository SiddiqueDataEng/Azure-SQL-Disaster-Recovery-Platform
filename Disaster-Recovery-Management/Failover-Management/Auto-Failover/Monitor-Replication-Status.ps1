# =====================================================
# Azure SQL Disaster Recovery Platform (ASDRP)
# Monitor Replication Status
# Production-Ready Enterprise SQL Disaster Recovery
# =====================================================

<#
.SYNOPSIS
    Monitors the replication status of Azure SQL Database geo-replication.

.DESCRIPTION
    This script continuously monitors the replication status between primary
    and secondary databases, providing real-time insights into replication
    health, lag, and performance metrics.

.PARAMETER ResourceGroupName
    The name of the resource group containing the primary database.

.PARAMETER ServerName
    The name of the primary SQL server.

.PARAMETER DatabaseName
    The name of the database to monitor.

.PARAMETER SecondaryResourceGroupName
    The name of the resource group for the secondary database.

.PARAMETER SecondaryServerName
    The name of the secondary SQL server.

.PARAMETER MonitoringDuration
    Duration to monitor in minutes (default: 60).

.PARAMETER RefreshInterval
    Refresh interval in seconds (default: 30).

.PARAMETER AlertThreshold
    Replication lag threshold in seconds for alerts (default: 300).

.EXAMPLE
    .\Monitor-Replication-Status.ps1 -ResourceGroupName "rg-primary" -ServerName "sql-primary" -DatabaseName "ProductionDB" -SecondaryResourceGroupName "rg-secondary" -SecondaryServerName "sql-secondary"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$ServerName,
    
    [Parameter(Mandatory = $true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory = $true)]
    [string]$SecondaryResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$SecondaryServerName,
    
    [Parameter(Mandatory = $false)]
    [int]$MonitoringDuration = 60,
    
    [Parameter(Mandatory = $false)]
    [int]$RefreshInterval = 30,
    
    [Parameter(Mandatory = $false)]
    [int]$AlertThreshold = 300
)

# Import required modules
Import-Module Az.Sql -Force
Import-Module Az.Resources -Force

# Set error action preference
$ErrorActionPreference = "Stop"

# Initialize monitoring variables
$startTime = Get-Date
$endTime = $startTime.AddMinutes($MonitoringDuration)
$alertCount = 0
$maxLag = 0
$minLag = [int]::MaxValue
$lagHistory = @()

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Azure SQL Disaster Recovery Platform" -ForegroundColor Cyan
    Write-Host "Replication Status Monitor" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Database: $DatabaseName" -ForegroundColor White
    Write-Host "Primary Server: $ServerName" -ForegroundColor White
    Write-Host "Secondary Server: $SecondaryServerName" -ForegroundColor White
    Write-Host "Monitoring Duration: $MonitoringDuration minutes" -ForegroundColor White
    Write-Host "Refresh Interval: $RefreshInterval seconds" -ForegroundColor White
    Write-Host "Alert Threshold: $AlertThreshold seconds" -ForegroundColor White
    Write-Host "Start Time: $startTime" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Verify databases exist
    Write-Host "Verifying database configuration..." -ForegroundColor Yellow
    
    $primaryDatabase = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $ServerName -DatabaseName $DatabaseName
    if (-not $primaryDatabase) {
        throw "Primary database '$DatabaseName' not found on server '$ServerName'"
    }
    
    $secondaryDatabase = Get-AzSqlDatabase -ResourceGroupName $SecondaryResourceGroupName -ServerName $SecondaryServerName -DatabaseName $DatabaseName
    if (-not $secondaryDatabase) {
        throw "Secondary database '$DatabaseName' not found on server '$SecondaryServerName'"
    }
    
    Write-Host "Database configuration verified." -ForegroundColor Green
    
    # Start monitoring loop
    Write-Host "`nStarting replication monitoring..." -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop monitoring early.`n" -ForegroundColor Yellow
    
    while ((Get-Date) -lt $endTime) {
        try {
            $currentTime = Get-Date
            
            # Get replication link status
            $replicationLink = Get-AzSqlDatabaseReplicationLink `
                -ResourceGroupName $ResourceGroupName `
                -ServerName $ServerName `
                -DatabaseName $DatabaseName `
                -PartnerResourceGroupName $SecondaryResourceGroupName `
                -PartnerServerName $SecondaryServerName
            
            $replicationLag = $replicationLink.ReplicationLagInSeconds
            $replicationState = $replicationLink.ReplicationState
            $partnerRole = $replicationLink.PartnerRole
            
            # Update statistics
            if ($replicationLag -gt $maxLag) { $maxLag = $replicationLag }
            if ($replicationLag -lt $minLag) { $minLag = $replicationLag }
            $lagHistory += $replicationLag
            
            # Check for alerts
            $alertStatus = ""
            if ($replicationLag -gt $AlertThreshold) {
                $alertCount++
                $alertStatus = " [ALERT]"
                Write-Host "ALERT: High replication lag detected!" -ForegroundColor Red
            }
            
            # Display current status
            $statusColor = if ($replicationLag -gt $AlertThreshold) { "Red" } elseif ($replicationLag -gt ($AlertThreshold * 0.7)) { "Yellow" } else { "Green" }
            
            Write-Host "[$($currentTime.ToString('HH:mm:ss'))] State: $replicationState | Lag: $replicationLag sec | Role: $partnerRole$alertStatus" -ForegroundColor $statusColor
            
            # Additional health checks
            if ($replicationState -eq "SUSPENDED") {
                Write-Host "WARNING: Replication is suspended!" -ForegroundColor Red
            }
            elseif ($replicationState -eq "PENDING") {
                Write-Host "INFO: Replication is pending initialization." -ForegroundColor Yellow
            }
            
            # Wait for next refresh
            Start-Sleep -Seconds $RefreshInterval
        }
        catch {
            Write-Warning "Error retrieving replication status: $($_.Exception.Message)"
            Start-Sleep -Seconds $RefreshInterval
        }
    }
    
    # Calculate final statistics
    $totalReadings = $lagHistory.Count
    $averageLag = if ($totalReadings -gt 0) { ($lagHistory | Measure-Object -Average).Average } else { 0 }
    $monitoringDurationActual = ((Get-Date) - $startTime).TotalMinutes
    
    # Display final summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Monitoring Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Database: $DatabaseName" -ForegroundColor White
    Write-Host "Monitoring Duration: $([math]::Round($monitoringDurationActual, 2)) minutes" -ForegroundColor White
    Write-Host "Total Readings: $totalReadings" -ForegroundColor White
    Write-Host "Average Lag: $([math]::Round($averageLag, 2)) seconds" -ForegroundColor White
    Write-Host "Minimum Lag: $minLag seconds" -ForegroundColor White
    Write-Host "Maximum Lag: $maxLag seconds" -ForegroundColor White
    Write-Host "Alert Count: $alertCount" -ForegroundColor White
    Write-Host "Alert Threshold: $AlertThreshold seconds" -ForegroundColor White
    
    # Health assessment
    $healthStatus = "HEALTHY"
    $healthColor = "Green"
    
    if ($alertCount -gt ($totalReadings * 0.1)) {
        $healthStatus = "UNHEALTHY"
        $healthColor = "Red"
    }
    elseif ($averageLag -gt ($AlertThreshold * 0.5)) {
        $healthStatus = "WARNING"
        $healthColor = "Yellow"
    }
    
    Write-Host "Overall Health: $healthStatus" -ForegroundColor $healthColor
    Write-Host "End Time: $(Get-Date)" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Return monitoring results
    return @{
        Database = $DatabaseName
        MonitoringDuration = $monitoringDurationActual
        TotalReadings = $totalReadings
        AverageLag = $averageLag
        MinimumLag = $minLag
        MaximumLag = $maxLag
        AlertCount = $alertCount
        AlertThreshold = $AlertThreshold
        HealthStatus = $healthStatus
        LagHistory = $lagHistory
    }
}
catch {
    Write-Error "Monitoring failed: $($_.Exception.Message)"
    throw
}