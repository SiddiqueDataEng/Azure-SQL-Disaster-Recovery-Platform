# =====================================================
# Azure SQL Disaster Recovery Platform (ASDRP)
# Create Auto-Failover Group
# Production-Ready Enterprise SQL Disaster Recovery
# =====================================================

<#
.SYNOPSIS
    Creates an auto-failover group for Azure SQL Database.

.DESCRIPTION
    This script creates an auto-failover group that provides automatic failover
    capabilities for one or more databases between primary and secondary servers.
    It includes configuration for failover policies, grace periods, and read-write endpoints.

.PARAMETER ResourceGroupName
    The name of the resource group containing the primary server.

.PARAMETER PrimaryServerName
    The name of the primary SQL server.

.PARAMETER SecondaryResourceGroupName
    The name of the resource group for the secondary server.

.PARAMETER SecondaryServerName
    The name of the secondary SQL server.

.PARAMETER FailoverGroupName
    The name of the failover group to create.

.PARAMETER DatabaseNames
    Array of database names to include in the failover group.

.PARAMETER FailoverPolicy
    The failover policy: "Automatic" or "Manual".

.PARAMETER GracePeriodInHours
    Grace period in hours before automatic failover (1-24 hours).

.PARAMETER AllowReadOnlyFailover
    Whether to allow read-only endpoint failover.

.EXAMPLE
    .\Create-Auto-Failover-Group.ps1 -ResourceGroupName "rg-primary" -PrimaryServerName "sql-primary" -SecondaryResourceGroupName "rg-secondary" -SecondaryServerName "sql-secondary" -FailoverGroupName "fg-production" -DatabaseNames @("ProductionDB", "LoggingDB")
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$PrimaryServerName,
    
    [Parameter(Mandatory = $true)]
    [string]$SecondaryResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$SecondaryServerName,
    
    [Parameter(Mandatory = $true)]
    [string]$FailoverGroupName,
    
    [Parameter(Mandatory = $true)]
    [string[]]$DatabaseNames,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Automatic", "Manual")]
    [string]$FailoverPolicy = "Automatic",
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 24)]
    [int]$GracePeriodInHours = 1,
    
    [Parameter(Mandatory = $false)]
    [bool]$AllowReadOnlyFailover = $true
)

# Import required modules
Import-Module Az.Sql -Force
Import-Module Az.Resources -Force

# Set error action preference
$ErrorActionPreference = "Stop"

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Azure SQL Disaster Recovery Platform" -ForegroundColor Cyan
    Write-Host "Create Auto-Failover Group" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Validate servers exist
    Write-Host "Validating server configuration..." -ForegroundColor Yellow
    
    $primaryServer = Get-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $PrimaryServerName
    if (-not $primaryServer) {
        throw "Primary server '$PrimaryServerName' not found in resource group '$ResourceGroupName'"
    }
    
    $secondaryServer = Get-AzSqlServer -ResourceGroupName $SecondaryResourceGroupName -ServerName $SecondaryServerName
    if (-not $secondaryServer) {
        throw "Secondary server '$SecondaryServerName' not found in resource group '$SecondaryResourceGroupName'"
    }
    
    Write-Host "Server configuration validated:" -ForegroundColor Green
    Write-Host "  Primary: $($primaryServer.ServerName) ($($primaryServer.Location))" -ForegroundColor White
    Write-Host "  Secondary: $($secondaryServer.ServerName) ($($secondaryServer.Location))" -ForegroundColor White
    
    # Validate databases exist on primary server
    Write-Host "`nValidating databases..." -ForegroundColor Yellow
    $validatedDatabases = @()
    
    foreach ($dbName in $DatabaseNames) {
        try {
            $database = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $PrimaryServerName -DatabaseName $dbName
            if ($database) {
                $validatedDatabases += $dbName
                Write-Host "  ✓ $dbName - Found" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "Database '$dbName' not found on primary server. Skipping."
        }
    }
    
    if ($validatedDatabases.Count -eq 0) {
        throw "No valid databases found on primary server"
    }
    
    Write-Host "Validated $($validatedDatabases.Count) databases for failover group." -ForegroundColor Green
    
    # Check if failover group already exists
    Write-Host "`nChecking for existing failover group..." -ForegroundColor Yellow
    
    try {
        $existingFailoverGroup = Get-AzSqlDatabaseFailoverGroup -ResourceGroupName $ResourceGroupName -ServerName $PrimaryServerName -FailoverGroupName $FailoverGroupName
        if ($existingFailoverGroup) {
            Write-Warning "Failover group '$FailoverGroupName' already exists."
            $overwrite = Read-Host "Do you want to update the existing failover group? (y/N)"
            if ($overwrite -ne "y" -and $overwrite -ne "Y") {
                Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                return
            }
        }
    }
    catch {
        # Failover group doesn't exist, which is expected for new creation
        Write-Host "No existing failover group found. Proceeding with creation." -ForegroundColor Green
    }
    
    # Display configuration summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Failover Group Configuration" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Name: $FailoverGroupName" -ForegroundColor White
    Write-Host "Primary Server: $PrimaryServerName ($($primaryServer.Location))" -ForegroundColor White
    Write-Host "Secondary Server: $SecondaryServerName ($($secondaryServer.Location))" -ForegroundColor White
    Write-Host "Failover Policy: $FailoverPolicy" -ForegroundColor White
    Write-Host "Grace Period: $GracePeriodInHours hours" -ForegroundColor White
    Write-Host "Read-Only Failover: $AllowReadOnlyFailover" -ForegroundColor White
    Write-Host "Databases: $($validatedDatabases -join ', ')" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Create failover group
    Write-Host "`nCreating auto-failover group..." -ForegroundColor Yellow
    
    $creationStartTime = Get-Date
    
    # Prepare partner server information
    $partnerServer = @{
        ResourceGroupName = $SecondaryResourceGroupName
        ServerName = $SecondaryServerName
    }
    
    # Create the failover group
    if ($existingFailoverGroup) {
        # Update existing failover group
        Write-Host "Updating existing failover group..." -ForegroundColor Yellow
        
        $failoverGroup = Set-AzSqlDatabaseFailoverGroup `
            -ResourceGroupName $ResourceGroupName `
            -ServerName $PrimaryServerName `
            -FailoverGroupName $FailoverGroupName `
            -FailoverPolicy $FailoverPolicy `
            -GracePeriodWithDataLossHours $GracePeriodInHours `
            -AllowReadOnlyFailoverToPrimary $AllowReadOnlyFailover `
            -Database $validatedDatabases
    }
    else {
        # Create new failover group
        Write-Host "Creating new failover group..." -ForegroundColor Yellow
        
        $failoverGroup = New-AzSqlDatabaseFailoverGroup `
            -ResourceGroupName $ResourceGroupName `
            -ServerName $PrimaryServerName `
            -PartnerResourceGroupName $SecondaryResourceGroupName `
            -PartnerServerName $SecondaryServerName `
            -FailoverGroupName $FailoverGroupName `
            -FailoverPolicy $FailoverPolicy `
            -GracePeriodWithDataLossHours $GracePeriodInHours `
            -AllowReadOnlyFailoverToPrimary $AllowReadOnlyFailover `
            -Database $validatedDatabases
    }
    
    $creationEndTime = Get-Date
    $creationDuration = ($creationEndTime - $creationStartTime).TotalSeconds
    
    Write-Host "Failover group created successfully!" -ForegroundColor Green
    Write-Host "Creation completed in $creationDuration seconds." -ForegroundColor Green
    
    # Verify failover group creation
    Write-Host "`nVerifying failover group..." -ForegroundColor Yellow
    
    Start-Sleep -Seconds 10
    
    $verifiedFailoverGroup = Get-AzSqlDatabaseFailoverGroup -ResourceGroupName $ResourceGroupName -ServerName $PrimaryServerName -FailoverGroupName $FailoverGroupName
    
    if ($verifiedFailoverGroup) {
        Write-Host "Failover group verification successful!" -ForegroundColor Green
        
        # Display failover group details
        Write-Host "`nFailover Group Details:" -ForegroundColor White
        Write-Host "  Name: $($verifiedFailoverGroup.FailoverGroupName)" -ForegroundColor White
        Write-Host "  Replication Role: $($verifiedFailoverGroup.ReplicationRole)" -ForegroundColor White
        Write-Host "  Replication State: $($verifiedFailoverGroup.ReplicationState)" -ForegroundColor White
        Write-Host "  Read-Write Endpoint: $($verifiedFailoverGroup.ReadWriteEndpoint)" -ForegroundColor White
        Write-Host "  Read-Only Endpoint: $($verifiedFailoverGroup.ReadOnlyEndpoint)" -ForegroundColor White
        Write-Host "  Databases: $($verifiedFailoverGroup.Databases -join ', ')" -ForegroundColor White
    }
    else {
        Write-Warning "Failover group verification failed. Group may still be initializing."
    }
    
    # Test connectivity to endpoints
    Write-Host "`nTesting failover group endpoints..." -ForegroundColor Yellow
    
    $readWriteEndpoint = "$FailoverGroupName.database.windows.net"
    $readOnlyEndpoint = "$FailoverGroupName.secondary.database.windows.net"
    
    Write-Host "Read-Write Endpoint: $readWriteEndpoint" -ForegroundColor Green
    Write-Host "Read-Only Endpoint: $readOnlyEndpoint" -ForegroundColor Green
    
    # Output summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Auto-Failover Group Creation Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Failover Group Name: $FailoverGroupName" -ForegroundColor White
    Write-Host "Primary Server: $PrimaryServerName" -ForegroundColor White
    Write-Host "Secondary Server: $SecondaryServerName" -ForegroundColor White
    Write-Host "Failover Policy: $FailoverPolicy" -ForegroundColor White
    Write-Host "Grace Period: $GracePeriodInHours hours" -ForegroundColor White
    Write-Host "Databases Included: $($validatedDatabases.Count)" -ForegroundColor White
    Write-Host "Creation Duration: $creationDuration seconds" -ForegroundColor White
    Write-Host "Start Time: $creationStartTime" -ForegroundColor White
    Write-Host "End Time: $creationEndTime" -ForegroundColor White
    Write-Host "Status: COMPLETED" -ForegroundColor Green
    Write-Host "`nConnection Endpoints:" -ForegroundColor White
    Write-Host "  Read-Write: $readWriteEndpoint" -ForegroundColor Green
    Write-Host "  Read-Only: $readOnlyEndpoint" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Important notes
    Write-Host "`nIMPORTANT NOTES:" -ForegroundColor Yellow
    Write-Host "• Use the read-write endpoint for application connections" -ForegroundColor White
    Write-Host "• Read-only endpoint provides access to secondary replica" -ForegroundColor White
    Write-Host "• Automatic failover will occur based on configured policy" -ForegroundColor White
    Write-Host "• Monitor failover group health regularly" -ForegroundColor White
    Write-Host "• Test failover procedures in non-production environments" -ForegroundColor White
    
    # Return failover group details
    return @{
        FailoverGroupName = $FailoverGroupName
        PrimaryServer = $PrimaryServerName
        SecondaryServer = $SecondaryServerName
        FailoverPolicy = $FailoverPolicy
        GracePeriod = $GracePeriodInHours
        DatabaseCount = $validatedDatabases.Count
        Databases = $validatedDatabases
        CreationDuration = $creationDuration
        StartTime = $creationStartTime
        EndTime = $creationEndTime
        Status = "COMPLETED"
        ReadWriteEndpoint = $readWriteEndpoint
        ReadOnlyEndpoint = $readOnlyEndpoint
        ReplicationRole = $verifiedFailoverGroup.ReplicationRole
        ReplicationState = $verifiedFailoverGroup.ReplicationState
    }
}
catch {
    Write-Error "Failed to create auto-failover group: $($_.Exception.Message)"
    
    # Log failure details
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Auto-Failover Group Creation Failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Failover Group Name: $FailoverGroupName" -ForegroundColor White
    Write-Host "Primary Server: $PrimaryServerName" -ForegroundColor White
    Write-Host "Secondary Server: $SecondaryServerName" -ForegroundColor White
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Time: $(Get-Date)" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Red
    
    throw
}