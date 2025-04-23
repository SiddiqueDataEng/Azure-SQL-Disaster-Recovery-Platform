# =====================================================
# Azure SQL Disaster Recovery Platform (ASDRP)
# Create Secondary Database for Geo-Replication
# Production-Ready Enterprise SQL Disaster Recovery
# =====================================================

<#
.SYNOPSIS
    Creates a secondary database for geo-replication in Azure SQL Database.

.DESCRIPTION
    This script creates a secondary database replica in a different Azure region
    for disaster recovery purposes. It establishes geo-replication between
    primary and secondary databases with automated failover capabilities.

.PARAMETER ResourceGroupName
    The name of the resource group containing the primary database.

.PARAMETER ServerName
    The name of the primary SQL server.

.PARAMETER DatabaseName
    The name of the database to replicate.

.PARAMETER SecondaryResourceGroupName
    The name of the resource group for the secondary database.

.PARAMETER SecondaryServerName
    The name of the secondary SQL server.

.PARAMETER SecondaryRegion
    The Azure region for the secondary database.

.EXAMPLE
    .\Create-Secondary-Database.ps1 -ResourceGroupName "rg-primary" -ServerName "sql-primary" -DatabaseName "ProductionDB" -SecondaryResourceGroupName "rg-secondary" -SecondaryServerName "sql-secondary" -SecondaryRegion "East US 2"
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
    
    [Parameter(Mandatory = $true)]
    [string]$SecondaryRegion
)

# Import required modules
Import-Module Az.Sql -Force
Import-Module Az.Resources -Force

# Set error action preference
$ErrorActionPreference = "Stop"

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Azure SQL Disaster Recovery Platform" -ForegroundColor Cyan
    Write-Host "Creating Secondary Database" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Verify primary database exists
    Write-Host "Verifying primary database exists..." -ForegroundColor Yellow
    $primaryDatabase = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $ServerName -DatabaseName $DatabaseName
    
    if (-not $primaryDatabase) {
        throw "Primary database '$DatabaseName' not found on server '$ServerName'"
    }
    
    Write-Host "Primary database verified: $($primaryDatabase.DatabaseName)" -ForegroundColor Green
    
    # Verify secondary server exists
    Write-Host "Verifying secondary server exists..." -ForegroundColor Yellow
    $secondaryServer = Get-AzSqlServer -ResourceGroupName $SecondaryResourceGroupName -ServerName $SecondaryServerName
    
    if (-not $secondaryServer) {
        throw "Secondary server '$SecondaryServerName' not found in resource group '$SecondaryResourceGroupName'"
    }
    
    Write-Host "Secondary server verified: $($secondaryServer.ServerName)" -ForegroundColor Green
    
    # Create secondary database with geo-replication
    Write-Host "Creating secondary database with geo-replication..." -ForegroundColor Yellow
    
    $secondaryDatabase = New-AzSqlDatabaseSecondary `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName `
        -DatabaseName $DatabaseName `
        -PartnerResourceGroupName $SecondaryResourceGroupName `
        -PartnerServerName $SecondaryServerName `
        -AllowConnections "All"
    
    Write-Host "Secondary database created successfully!" -ForegroundColor Green
    
    # Verify replication status
    Write-Host "Verifying replication status..." -ForegroundColor Yellow
    
    $replicationLink = Get-AzSqlDatabaseReplicationLink `
        -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName `
        -DatabaseName $DatabaseName `
        -PartnerResourceGroupName $SecondaryResourceGroupName `
        -PartnerServerName $SecondaryServerName
    
    Write-Host "Replication Status: $($replicationLink.ReplicationState)" -ForegroundColor Green
    Write-Host "Partner Role: $($replicationLink.PartnerRole)" -ForegroundColor Green
    Write-Host "Replication Lag: $($replicationLink.ReplicationLagInSeconds) seconds" -ForegroundColor Green
    
    # Output summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Secondary Database Creation Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Primary Database: $DatabaseName" -ForegroundColor White
    Write-Host "Primary Server: $ServerName" -ForegroundColor White
    Write-Host "Primary Region: $($primaryDatabase.Location)" -ForegroundColor White
    Write-Host "Secondary Server: $SecondaryServerName" -ForegroundColor White
    Write-Host "Secondary Region: $SecondaryRegion" -ForegroundColor White
    Write-Host "Replication State: $($replicationLink.ReplicationState)" -ForegroundColor White
    Write-Host "Creation Time: $(Get-Date)" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    
    return $secondaryDatabase
}
catch {
    Write-Error "Failed to create secondary database: $($_.Exception.Message)"
    throw
}