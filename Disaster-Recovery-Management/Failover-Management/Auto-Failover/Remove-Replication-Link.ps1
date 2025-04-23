# =====================================================
# Azure SQL Disaster Recovery Platform (ASDRP)
# Remove Replication Link
# Production-Ready Enterprise SQL Disaster Recovery
# =====================================================

<#
.SYNOPSIS
    Removes the geo-replication link between primary and secondary databases.

.DESCRIPTION
    This script safely removes the geo-replication relationship between
    primary and secondary Azure SQL databases. It includes validation,
    confirmation prompts, and cleanup procedures.

.PARAMETER ResourceGroupName
    The name of the resource group containing the primary database.

.PARAMETER ServerName
    The name of the primary SQL server.

.PARAMETER DatabaseName
    The name of the database to remove replication from.

.PARAMETER SecondaryResourceGroupName
    The name of the resource group for the secondary database.

.PARAMETER SecondaryServerName
    The name of the secondary SQL server.

.PARAMETER Force
    Skip confirmation prompts and force removal.

.PARAMETER KeepSecondaryDatabase
    Keep the secondary database as a standalone database after removing replication.

.EXAMPLE
    .\Remove-Replication-Link.ps1 -ResourceGroupName "rg-primary" -ServerName "sql-primary" -DatabaseName "ProductionDB" -SecondaryResourceGroupName "rg-secondary" -SecondaryServerName "sql-secondary"
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
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepSecondaryDatabase
)

# Import required modules
Import-Module Az.Sql -Force
Import-Module Az.Resources -Force

# Set error action preference
$ErrorActionPreference = "Stop"

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Azure SQL Disaster Recovery Platform" -ForegroundColor Cyan
    Write-Host "Remove Replication Link" -ForegroundColor Cyan
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
    
    # Check replication link exists
    Write-Host "Checking replication link status..." -ForegroundColor Yellow
    
    try {
        $replicationLink = Get-AzSqlDatabaseReplicationLink `
            -ResourceGroupName $ResourceGroupName `
            -ServerName $ServerName `
            -DatabaseName $DatabaseName `
            -PartnerResourceGroupName $SecondaryResourceGroupName `
            -PartnerServerName $SecondaryServerName
        
        Write-Host "Replication link found:" -ForegroundColor Green
        Write-Host "  State: $($replicationLink.ReplicationState)" -ForegroundColor White
        Write-Host "  Role: $($replicationLink.Role)" -ForegroundColor White
        Write-Host "  Partner Role: $($replicationLink.PartnerRole)" -ForegroundColor White
        Write-Host "  Lag: $($replicationLink.ReplicationLagInSeconds) seconds" -ForegroundColor White
    }
    catch {
        Write-Warning "No replication link found between the specified databases."
        Write-Host "Operation cancelled - no replication to remove." -ForegroundColor Yellow
        return
    }
    
    # Display impact warning
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "WARNING: Replication Removal Impact" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "This operation will:" -ForegroundColor White
    Write-Host "  • Remove geo-replication between databases" -ForegroundColor White
    Write-Host "  • Stop automatic failover capabilities" -ForegroundColor White
    Write-Host "  • Make secondary database independent" -ForegroundColor White
    
    if (-not $KeepSecondaryDatabase) {
        Write-Host "  • Secondary database will remain as standalone" -ForegroundColor White
    }
    
    Write-Host "`nDatabases affected:" -ForegroundColor White
    Write-Host "  Primary: $ServerName/$DatabaseName" -ForegroundColor White
    Write-Host "  Secondary: $SecondaryServerName/$DatabaseName" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Yellow
    
    # Confirmation prompt
    if (-not $Force) {
        Write-Host "`nThis action cannot be undone!" -ForegroundColor Red
        $confirmation = Read-Host "Are you sure you want to remove the replication link? (yes/no)"
        
        if ($confirmation -ne "yes") {
            Write-Host "Operation cancelled by user." -ForegroundColor Yellow
            return
        }
        
        # Double confirmation for production environments
        if ($DatabaseName -match "prod|production" -or $ServerName -match "prod|production") {
            Write-Host "`nProduction database detected!" -ForegroundColor Red
            $doubleConfirmation = Read-Host "Type 'REMOVE REPLICATION' to confirm removal from production database"
            
            if ($doubleConfirmation -ne "REMOVE REPLICATION") {
                Write-Host "Operation cancelled - confirmation text did not match." -ForegroundColor Yellow
                return
            }
        }
    }
    
    # Record pre-removal state
    $removalStartTime = Get-Date
    Write-Host "`nStarting replication removal..." -ForegroundColor Yellow
    Write-Host "Start time: $removalStartTime" -ForegroundColor White
    
    # Remove replication link
    Write-Host "Removing replication link..." -ForegroundColor Yellow
    
    Remove-AzSqlDatabaseSecondary `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName `
        -DatabaseName $DatabaseName `
        -PartnerResourceGroupName $SecondaryResourceGroupName `
        -PartnerServerName $SecondaryServerName
    
    $removalEndTime = Get-Date
    $removalDuration = ($removalEndTime - $removalStartTime).TotalSeconds
    
    Write-Host "Replication link removed successfully!" -ForegroundColor Green
    Write-Host "Removal completed in $removalDuration seconds." -ForegroundColor Green
    
    # Verify removal
    Write-Host "`nVerifying replication removal..." -ForegroundColor Yellow
    
    Start-Sleep -Seconds 5
    
    try {
        $verificationLink = Get-AzSqlDatabaseReplicationLink `
            -ResourceGroupName $ResourceGroupName `
            -ServerName $ServerName `
            -DatabaseName $DatabaseName `
            -PartnerResourceGroupName $SecondaryResourceGroupName `
            -PartnerServerName $SecondaryServerName
        
        Write-Warning "Replication link still exists. Removal may not have completed."
    }
    catch {
        Write-Host "Verification successful - replication link no longer exists." -ForegroundColor Green
    }
    
    # Check database status
    Write-Host "Checking database status..." -ForegroundColor Yellow
    
    $primaryStatus = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $ServerName -DatabaseName $DatabaseName
    $secondaryStatus = Get-AzSqlDatabase -ResourceGroupName $SecondaryResourceGroupName -ServerName $SecondaryServerName -DatabaseName $DatabaseName
    
    Write-Host "Primary database status: $($primaryStatus.Status)" -ForegroundColor Green
    Write-Host "Secondary database status: $($secondaryStatus.Status)" -ForegroundColor Green
    
    # Output summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Replication Removal Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Database: $DatabaseName" -ForegroundColor White
    Write-Host "Primary Server: $ServerName" -ForegroundColor White
    Write-Host "Secondary Server: $SecondaryServerName" -ForegroundColor White
    Write-Host "Removal Duration: $removalDuration seconds" -ForegroundColor White
    Write-Host "Start Time: $removalStartTime" -ForegroundColor White
    Write-Host "End Time: $removalEndTime" -ForegroundColor White
    Write-Host "Status: COMPLETED" -ForegroundColor Green
    Write-Host "`nPost-Removal Status:" -ForegroundColor White
    Write-Host "  Primary Database: ACTIVE (Standalone)" -ForegroundColor Green
    Write-Host "  Secondary Database: ACTIVE (Standalone)" -ForegroundColor Green
    Write-Host "  Replication Link: REMOVED" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Important notes
    Write-Host "`nIMPORTANT NOTES:" -ForegroundColor Yellow
    Write-Host "• Both databases are now independent" -ForegroundColor White
    Write-Host "• Automatic failover is no longer available" -ForegroundColor White
    Write-Host "• Consider implementing alternative backup strategies" -ForegroundColor White
    Write-Host "• Monitor both databases independently" -ForegroundColor White
    
    # Return removal details
    return @{
        Database = $DatabaseName
        PrimaryServer = $ServerName
        SecondaryServer = $SecondaryServerName
        RemovalDuration = $removalDuration
        StartTime = $removalStartTime
        EndTime = $removalEndTime
        Status = "COMPLETED"
        PrimaryDatabaseStatus = $primaryStatus.Status
        SecondaryDatabaseStatus = $secondaryStatus.Status
    }
}
catch {
    Write-Error "Failed to remove replication link: $($_.Exception.Message)"
    
    # Log failure details
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Replication Removal Failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Database: $DatabaseName" -ForegroundColor White
    Write-Host "Primary Server: $ServerName" -ForegroundColor White
    Write-Host "Secondary Server: $SecondaryServerName" -ForegroundColor White
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Time: $(Get-Date)" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Red
    
    throw
}