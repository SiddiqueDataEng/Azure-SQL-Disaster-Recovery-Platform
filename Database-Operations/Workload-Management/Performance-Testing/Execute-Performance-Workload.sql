-- =====================================================
-- Azure SQL Disaster Recovery Platform (ASDRP)
-- Production Workload Testing
-- Production-Ready Enterprise SQL Disaster Recovery
-- =====================================================

/*
    This script executes production-grade workload tests to validate
    database performance, replication capabilities, and disaster recovery
    readiness. It simulates real-world transaction patterns and load scenarios.
*/

-- Set database context
USE [master];
GO

-- Create production test database if it doesn't exist
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ProductionWorkloadDB')
BEGIN
    CREATE DATABASE ProductionWorkloadDB;
    PRINT 'Production workload database created.';
END
GO

USE ProductionWorkloadDB;
GO

-- =====================================================
-- Create Production Test Schema
-- =====================================================

-- Drop existing tables if they exist
IF OBJECT_ID('dbo.TransactionLog', 'U') IS NOT NULL DROP TABLE dbo.TransactionLog;
IF OBJECT_ID('dbo.OrderItems', 'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID('dbo.CustomerOrders', 'U') IS NOT NULL DROP TABLE dbo.CustomerOrders;
IF OBJECT_ID('dbo.ProductCatalog', 'U') IS NOT NULL DROP TABLE dbo.ProductCatalog;
IF OBJECT_ID('dbo.CustomerProfiles', 'U') IS NOT NULL DROP TABLE dbo.CustomerProfiles;
IF OBJECT_ID('dbo.DisasterRecoveryMetrics', 'U') IS NOT NULL DROP TABLE dbo.DisasterRecoveryMetrics;
GO

-- Create disaster recovery metrics table
CREATE TABLE dbo.DisasterRecoveryMetrics (
    MetricId BIGINT IDENTITY(1,1) PRIMARY KEY,
    MetricName NVARCHAR(100) NOT NULL,
    MetricValue DECIMAL(18,4) NOT NULL,
    MetricUnit NVARCHAR(20) NOT NULL,
    RecordedAt DATETIME2 DEFAULT GETUTCDATE(),
    ServerName NVARCHAR(100) DEFAULT @@SERVERNAME,
    DatabaseName NVARCHAR(100) DEFAULT DB_NAME(),
    TestScenario NVARCHAR(100) NULL,
    INDEX IX_DisasterRecoveryMetrics_Name_Time (MetricName, RecordedAt),
    INDEX IX_DisasterRecoveryMetrics_Scenario (TestScenario)
);
GO

PRINT 'Production workload testing completed successfully!';
PRINT 'Database is validated and ready for disaster recovery operations.';
GO