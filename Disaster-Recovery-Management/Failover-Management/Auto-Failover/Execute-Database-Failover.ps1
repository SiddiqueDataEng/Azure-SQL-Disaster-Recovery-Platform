# =====================================================
# Azure SQL Disaster Recovery Platform (ASDRP)
# Execute Database Failover
# Production-Ready Enterprise SQL Disaster Recovery
# =====================================================

<#
.SYNOPSIS
    Executes a failover operation for Azure SQL Database geo-replication.

.DESCRIPTION
    This script performs a planned or forced failover from the primary database
    to the secondary database. It includes pre-failover validation, failover
    execution, and post-failover verification.

.PARAMETER ResourceGroupName
    The name of the resource group containing the primary database.

.PARAMETER ServerName
    The name of the primary SQL server.

.PARAMETER DatabaseName
    The name of the database to failover.

.PARAMETER SecondaryResourceGroupName
    The name of the resource group for the secondary database.

.PARAMETER SecondaryServerName
    The name of the secondary SQL server.

.PARAMETER FailoverType
    The type of failover: "Planned" or "Forced".

.PARAMETER AllowDataLoss
    Whether to allow data loss during forced failover.

.EXAMPLE
    .\Execute-Database-Failover.ps1 -ResourceGroupName "rg-primary" -ServerName "sql-primary" -DatabaseName "ProductionDB" -SecondaryResourceGroupName "rg-secondary" -SecondaryServerName "sql-secondary" -FailoverType "Planned"
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
    [ValidateSet("Planned", "Forced")]
    [string]$FailoverType = "Planned",
    
    [Parameter(Mandatory = $false)]
    [bool]$AllowDataLoss = $false
)

# Import required modules
Import-Module Az.Sql -Force
Import-Module Az.Resources -Force

# Set error action preference
$ErrorActionPreference = "Stop"

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Azure SQL Disaster Recovery Platform" -ForegroundColor Cyan
    Write-Host "Executing Database Failover" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Pre-failover validation
    Write-Host "Performing pre-failover validation..." -ForegroundColor Yellow
    
    # Verify primary database exists
    $primaryDatabase = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $ServerName -DatabaseName $DatabaseName
    if (-not $primaryDatabase) {
        throw "Primary database '$DatabaseName' not found on server '$ServerName'"
    }
    
    # Verify secondary database exists
    $secondaryDatabase = Get-AzSqlDatabase -ResourceGroupName $SecondaryResourceGroupName -ServerName $SecondaryServerName -DatabaseName $DatabaseName
    if (-not $secondaryDatabase) {
        throw "Secondary database '$DatabaseName' not found on server '$SecondaryServerName'"
    }
    
    # Check replication status
    $replicationLink = Get-AzSqlDatabaseReplicationLink `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName `
        -DatabaseName $DatabaseName `
        -PartnerResourceGroupName $SecondaryResourceGroupName `
        -PartnerServerName $SecondaryServerName
    
    Write-Host "Current Replication Status: $($replicationLink.ReplicationState)" -ForegroundColor Green
    Write-Host "Replication Lag: $($replicationLink.ReplicationLagInSeconds) seconds" -ForegroundColor Green
    
    # Validate replication health for planned failover
    if ($FailoverType -eq "Planned" -and $replicationLink.ReplicationState -ne "CATCH_UP") {
        if ($replicationLink.ReplicationLagInSeconds -gt 300) {
            Write-Warning "High replication lag detected: $($replicationLink.ReplicationLagInSeconds) seconds"
            $continue = Read-Host "Continue with failover? (y/N)"
            if ($continue -ne "y" -and $continue -ne "Y") {
                Write-Host "Failover cancelled by user." -ForegroundColor Yellow
                return
            }
        }
    }
    
    # Record pre-failover state
    $preFailoverTime = Get-Date
    Write-Host "Pre-failover timestamp: $preFailoverTime" -ForegroundColor White
    
    # Execute failover
    Write-Host "`nExecuting $FailoverType failover..." -ForegroundColor Yellow
    
    if ($FailoverType -eq "Planned") {
        # Planned failover (no data loss)
        $failoverResult = Set-AzSqlDatabaseSecondary `
            -ResourceGroupName $SecondaryResourceGroupName `
            -ServerName $SecondaryServerName `
            -DatabaseName $DatabaseName `
            -Failover
    }
    else {
        # Forced failover (potential data loss)
        if (-not $AllowDataLoss) {
            Write-Warning "Forced failover may result in data loss!"
            $confirm = Read-Host "Are you sure you want to proceed? Type 'CONFIRM' to continue"
            if ($confirm -ne "CONFIRM") {
                Write-Host "Failover cancelled by user." -ForegroundColor Yellow
                return
            }
        }
        
        $failoverResult = Set-AzSqlDatabaseSecondary `
            -ResourceGroupName $SecondaryResourceGroupName `
            -ServerName $SecondaryServerName `
            -DatabaseName $DatabaseName `
            -Failover `
            -AllowDataLoss
    }
    
    $postFailoverTime = Get-Date
    $failoverDuration = ($postFailoverTime - $preFailoverTime).TotalSeconds
    
    Write-Host "Failover completed in $failoverDuration seconds!" -ForegroundColor Green
    
    # Post-failover verification
    Write-Host "`nPerforming post-failover verification..." -ForegroundColor Yellow
    
    # Wait for failover to complete
    Start-Sleep -Seconds 10
    
    # Verify new primary database
    $newPrimaryDatabase = Get-AzSqlDatabase -ResourceGroupName $SecondaryResourceGroupName -ServerName $SecondaryServerName -DatabaseName $DatabaseName
    
    # Check new replication status
    try {
        $newReplicationLink = Get-AzSqlDatabaseReplicationLink `
            -ResourceGroupName $SecondaryResourceGroupName `
            -ServerName $SecondaryServerName `
            -DatabaseName $DatabaseName `
            -PartnerResourceGroupName $ResourceGroupName `
            -PartnerServerName $ServerName
        
        Write-Host "New Replication Status: $($newReplicationLink.ReplicationState)" -ForegroundColor Green
        Write-Host "New Primary Role: $($newReplicationLink.Role)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not retrieve new replication link status. This is normal immediately after failover."
    }
    
    # Test connectivity to new primary
    Write-Host "Testing connectivity to new primary database..." -ForegroundColor Yellow
    
    try {
        $connectionTest = Test-AzSqlDatabaseConnection -ResourceGroupName $SecondaryResourceGroupName -ServerName $SecondaryServerName -DatabaseName $DatabaseName
        Write-Host "Connectivity test: PASSED" -ForegroundColor Green
    }
    catch {
        Write-Warning "Connectivity test failed. Database may still be initializing."
    }
    
    # Output summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Failover Operation Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Database: $DatabaseName" -ForegroundColor White
    Write-Host "Failover Type: $FailoverType" -ForegroundColor White
    Write-Host "Previous Primary: $ServerName" -ForegroundColor White
    Write-Host "New Primary: $SecondaryServerName" -ForegroundColor White
    Write-Host "Failover Duration: $failoverDuration seconds" -ForegroundColor White
    Write-Host "Start Time: $preFailoverTime" -ForegroundColor White
    Write-Host "End Time: $postFailoverTime" -ForegroundColor White
    Write-Host "Status: COMPLETED" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Return failover details
    return @{
        Database = $DatabaseName
        FailoverType = $FailoverType
        PreviousPrimary = $ServerName
        NewPrimary = $SecondaryServerName
        Duration = $failoverDuration
        StartTime = $preFailoverTime
        EndTime = $postFailoverTime
        Status = "COMPLETED"
    }
}
catch {
    Write-Error "Failover operation failed: $($_.Exception.Message)"
    
    # Log failure details
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Failover Operation Failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Database: $DatabaseName" -ForegroundColor White
    Write-Host "Failover Type: $FailoverType" -ForegroundColor White
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Time: $(Get-Date)" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Red
    
    throw
}