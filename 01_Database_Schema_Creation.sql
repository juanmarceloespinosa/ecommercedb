-- =============================================
-- E-Commerce Database Schema Creation
-- High-Performance, Scalable Design for SQL Server
-- =============================================

-- Create the database with optimized settings
USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'ECommerceDB')
    DROP DATABASE ECommerceDB;
GO

CREATE DATABASE ECommerceDB
ON 
( NAME = 'ECommerceDB_Data',
  FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\ECommerceDB_Data.mdf',
  SIZE = 1GB,
  MAXSIZE = 100GB,
  FILEGROWTH = 100MB )
LOG ON 
( NAME = 'ECommerceDB_Log',
  FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\ECommerceDB_Log.ldf',
  SIZE = 100MB,
  MAXSIZE = 10GB,
  FILEGROWTH = 10MB );
GO

-- Set database options for performance
ALTER DATABASE ECommerceDB SET RECOVERY FULL;
ALTER DATABASE ECommerceDB SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE ECommerceDB SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE ECommerceDB SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE ECommerceDB SET AUTO_UPDATE_STATISTICS_ASYNC ON;
GO

USE ECommerceDB;
GO

-- =============================================
-- Create schemas for organization
-- =============================================
CREATE SCHEMA Sales AUTHORIZATION dbo;
GO
CREATE SCHEMA Inventory AUTHORIZATION dbo;
GO
CREATE SCHEMA Customer AUTHORIZATION dbo;
GO
CREATE SCHEMA Security AUTHORIZATION dbo;
GO

-- =============================================
-- Create master key for encryption
-- =============================================
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'ECommerce@2024#SecureKey!';
GO

-- =============================================
-- Create certificate for column encryption
-- =============================================
CREATE CERTIFICATE ECommerceCert
WITH SUBJECT = 'ECommerce Data Protection Certificate';
GO

-- =============================================
-- Create symmetric key for sensitive data
-- =============================================
CREATE SYMMETRIC KEY ECommerceSymmetricKey
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE ECommerceCert;
GO

-- =============================================
-- Create Category Table (Hierarchical)
-- =============================================
CREATE TABLE Inventory.Category (
    CategoryID INT IDENTITY(1,1) NOT NULL,
    CategoryName NVARCHAR(50) NOT NULL,
    CategoryDescription NVARCHAR(MAX) NULL,
    ParentCategoryID INT NULL,
    CategoryLevel AS (
        CASE 
            WHEN ParentCategoryID IS NULL THEN 0
            ELSE 1
        END
    ) PERSISTED,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    ModifiedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_Category PRIMARY KEY CLUSTERED (CategoryID),
    CONSTRAINT FK_Category_Parent FOREIGN KEY (ParentCategoryID) 
        REFERENCES Inventory.Category(CategoryID),
    CONSTRAINT CHK_Category_NotSelfParent CHECK (CategoryID != ParentCategoryID),
    CONSTRAINT UQ_Category_Name UNIQUE (CategoryName, ParentCategoryID)
);
GO

-- =============================================
-- Create Product Table with partitioning support
-- =============================================
CREATE TABLE Inventory.Product (
    ProductID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ProductName NVARCHAR(255) NOT NULL,
    CategoryID INT NOT NULL,
    Price DECIMAL(12,4) NOT NULL,
    StockQuantity INT NOT NULL DEFAULT 0,
    ReorderLevel INT NOT NULL DEFAULT 10, -- Minimun stock to reorder
    ProductDescription NVARCHAR(MAX) NULL,
    ProductImage VARBINARY(MAX) NULL,
    ProductSKU NVARCHAR(50) NOT NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    ModifiedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
	IsLowStock AS CASE WHEN StockQuantity <= ReorderLevel THEN 1 ELSE 0 END PERSISTED, -- Added computed column
    RowVersion ROWVERSION,
    
    CONSTRAINT PK_Product PRIMARY KEY CLUSTERED (ProductID),
    CONSTRAINT FK_Product_Category FOREIGN KEY (CategoryID) 
        REFERENCES Inventory.Category(CategoryID),
    CONSTRAINT CHK_Product_Price CHECK (Price > 0),
    CONSTRAINT CHK_Product_Stock CHECK (StockQuantity >= 0),
    CONSTRAINT CHK_Product_ReorderLevel CHECK (ReorderLevel >= 0),
    CONSTRAINT UQ_Product_SKU UNIQUE (ProductSKU)
);
GO

-- =============================================
-- Create Customer Table with encrypted sensitive data
-- =============================================
CREATE TABLE Customer.Customer (
    CustomerID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    CustomerName NVARCHAR(100) NOT NULL,
    Email VARBINARY(256) NOT NULL, -- Encrypted
    EmailHash AS CAST(HASHBYTES('SHA2_256', Email) AS BINARY(32)) PERSISTED, -- Fixed size for indexing
    PhoneNumber VARBINARY(128) NULL, -- Encrypted
    Address NVARCHAR(200) NULL,
    ShippingAddress NVARCHAR(200) NULL,
    BillingAddress NVARCHAR(200) NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    ModifiedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    LastLoginDate DATETIME2(3) NULL,
    RowVersion ROWVERSION,
    
    CONSTRAINT PK_Customer PRIMARY KEY CLUSTERED (CustomerID),
    CONSTRAINT UQ_Customer_EmailHash UNIQUE (EmailHash)
);
GO

-- =============================================
-- Create ShippingAddress Table
-- =============================================
CREATE TABLE Customer.ShippingAddress (
    ShippingAddressID INT IDENTITY(1,1) NOT NULL,
    CustomerID UNIQUEIDENTIFIER NOT NULL,
    AddressLine1 NVARCHAR(100) NOT NULL,
    AddressLine2 NVARCHAR(100) NULL,
    City NVARCHAR(50) NOT NULL,
    StateProvince NVARCHAR(50) NOT NULL,
    PostalCode NVARCHAR(20) NOT NULL,
    Country NVARCHAR(50) NOT NULL DEFAULT 'USA',
    AddressType NVARCHAR(20) NOT NULL DEFAULT 'Shipping',
    IsDefault BIT NOT NULL DEFAULT 0,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_ShippingAddress PRIMARY KEY CLUSTERED (ShippingAddressID),
    CONSTRAINT FK_ShippingAddress_Customer FOREIGN KEY (CustomerID) 
        REFERENCES Customer.Customer(CustomerID),
    CONSTRAINT CHK_ShippingAddress_Type CHECK (AddressType IN ('Shipping', 'Billing', 'Both'))
);
GO

-- =============================================
-- Create BillingAddress Table
-- =============================================
CREATE TABLE Customer.BillingAddress (
    BillingAddressID INT IDENTITY(1,1) NOT NULL,
    CustomerID UNIQUEIDENTIFIER NOT NULL,
    AddressLine1 NVARCHAR(100) NOT NULL,
    AddressLine2 NVARCHAR(100) NULL,
    City NVARCHAR(50) NOT NULL,
    StateProvince NVARCHAR(50) NOT NULL,
    PostalCode NVARCHAR(20) NOT NULL,
    Country NVARCHAR(50) NOT NULL DEFAULT 'USA',
    IsDefault BIT NOT NULL DEFAULT 0,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_BillingAddress PRIMARY KEY CLUSTERED (BillingAddressID),
    CONSTRAINT FK_BillingAddress_Customer FOREIGN KEY (CustomerID) 
        REFERENCES Customer.Customer(CustomerID)
);
GO

-- =============================================
-- Create Order Table with partitioning by date
-- =============================================
CREATE PARTITION FUNCTION pf_OrderDate (DATETIME2(3))
AS RANGE RIGHT FOR VALUES 
('2024-01-01', '2024-04-01', '2024-07-01', '2024-10-01', '2025-01-01');
GO

CREATE PARTITION SCHEME ps_OrderDate
AS PARTITION pf_OrderDate
ALL TO ([PRIMARY]);
GO

CREATE TABLE Sales.[Order] (
    OrderID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    CustomerID UNIQUEIDENTIFIER NOT NULL,
    OrderDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    OrderStatus NVARCHAR(50) NOT NULL DEFAULT 'Pending',
    ShippingAddressID INT NULL,
    BillingAddressID INT NULL,
    SubTotal DECIMAL(12,4) NOT NULL DEFAULT 0,
    TaxAmount DECIMAL(12,4) NOT NULL DEFAULT 0,
    ShippingAmount DECIMAL(12,4) NOT NULL DEFAULT 0,
    DiscountAmount DECIMAL(12,4) NOT NULL DEFAULT 0,
    TotalAmount DECIMAL(12,4) NOT NULL DEFAULT 0,
    PaymentStatus NVARCHAR(50) NOT NULL DEFAULT 'Pending',
    ShippingMethod NVARCHAR(50) NULL,
    TrackingNumber NVARCHAR(100) NULL,
    ExpectedDeliveryDate DATETIME2(3) NULL,
    ActualDeliveryDate DATETIME2(3) NULL,
    Notes NVARCHAR(500) NULL,
    CreatedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    ModifiedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    RowVersion ROWVERSION,
    
    CONSTRAINT PK_Order PRIMARY KEY CLUSTERED (OrderID, OrderDate),
    CONSTRAINT FK_Order_Customer FOREIGN KEY (CustomerID) 
        REFERENCES Customer.Customer(CustomerID),
    CONSTRAINT FK_Order_ShippingAddress FOREIGN KEY (ShippingAddressID) 
        REFERENCES Customer.ShippingAddress(ShippingAddressID),
    CONSTRAINT FK_Order_BillingAddress FOREIGN KEY (BillingAddressID) 
        REFERENCES Customer.BillingAddress(BillingAddressID),
    CONSTRAINT CHK_Order_Status CHECK (OrderStatus IN ('Pending', 'Processing', 'Shipped', 'Delivered', 'Cancelled', 'Returned')),
    CONSTRAINT CHK_Order_PaymentStatus CHECK (PaymentStatus IN ('Pending', 'Authorized', 'Captured', 'Failed', 'Refunded')),
    CONSTRAINT CHK_Order_Amounts CHECK (SubTotal >= 0 AND TaxAmount >= 0 AND ShippingAmount >= 0 AND DiscountAmount >= 0 AND TotalAmount >= 0),
    CONSTRAINT CHK_Order_DeliveryDates CHECK (ExpectedDeliveryDate IS NULL OR ExpectedDeliveryDate > OrderDate),
    CONSTRAINT CHK_Order_ActualDeliveryDate CHECK (ActualDeliveryDate IS NULL OR ActualDeliveryDate >= OrderDate)
) ON ps_OrderDate(OrderDate);
GO
CREATE UNIQUE NONCLUSTERED INDEX UQ_Order_OrderID 
ON Sales.[Order] (OrderID, OrderDate);
GO

-- =============================================
-- Create OrderDetail Table
-- =============================================
CREATE TABLE Sales.OrderDetail (
    OrderDetailID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    OrderID UNIQUEIDENTIFIER NOT NULL,
    ProductID UNIQUEIDENTIFIER NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(12,4) NOT NULL,
    DiscountAmount DECIMAL(12,4) NOT NULL DEFAULT 0,
    LineTotal AS (Quantity * UnitPrice - DiscountAmount) PERSISTED,
    CreatedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    
    CONSTRAINT PK_OrderDetail PRIMARY KEY CLUSTERED (OrderDetailID),
    CONSTRAINT FK_OrderDetail_Product FOREIGN KEY (ProductID) 
        REFERENCES Inventory.Product(ProductID),
    CONSTRAINT CHK_OrderDetail_Quantity CHECK (Quantity > 0),
    CONSTRAINT CHK_OrderDetail_UnitPrice CHECK (UnitPrice > 0),
    CONSTRAINT CHK_OrderDetail_DiscountAmount CHECK (DiscountAmount >= 0 AND DiscountAmount <= (Quantity * UnitPrice))
);
GO

-- =============================================
-- Create Inventory Transaction Log for audit trail
-- =============================================
CREATE TABLE Inventory.InventoryTransaction (
    TransactionID BIGINT IDENTITY(1,1) NOT NULL,
    ProductID UNIQUEIDENTIFIER NOT NULL,
    TransactionType NVARCHAR(20) NOT NULL,
    Quantity INT NOT NULL,
    PreviousStock INT NOT NULL,
    NewStock INT NOT NULL,
    ReferenceID UNIQUEIDENTIFIER NULL, -- OrderID or other reference
    ReferenceType NVARCHAR(50) NULL, -- 'Order', 'Return', 'Adjustment', etc.
    TransactionDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    UserId NVARCHAR(50) NOT NULL DEFAULT SYSTEM_USER,
    Notes NVARCHAR(500) NULL,
    
    CONSTRAINT PK_InventoryTransaction PRIMARY KEY CLUSTERED (TransactionID),
    CONSTRAINT FK_InventoryTransaction_Product FOREIGN KEY (ProductID) 
        REFERENCES Inventory.Product(ProductID),
    CONSTRAINT CHK_InventoryTransaction_Type CHECK (TransactionType IN ('Sale', 'Return', 'Adjustment', 'Restock', 'Damage', 'Transfer'))
);
GO

-- =============================================
-- Create audit table for sensitive operations
-- =============================================
CREATE TABLE Security.AuditLog (
    AuditID BIGINT IDENTITY(1,1) NOT NULL,
    TableName NVARCHAR(50) NOT NULL,
    Operation NVARCHAR(15) NOT NULL,
    PrimaryKeyValue NVARCHAR(50) NOT NULL,
    OldValues NVARCHAR(MAX) NULL,
    NewValues NVARCHAR(MAX) NULL,
    ChangedBy NVARCHAR(50) NOT NULL DEFAULT SYSTEM_USER,
    ChangedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    Application NVARCHAR(50) NULL DEFAULT APP_NAME(),
    
    CONSTRAINT PK_AuditLog PRIMARY KEY CLUSTERED (AuditID),
    CONSTRAINT CHK_AuditLog_Operation CHECK (Operation IN ('INSERT', 'UPDATE', 'DELETE', 'FIX', 'MAINTENANCE', 'STOCK_ALERT'))
);
GO

CREATE TABLE Sales.ProductReturn (
    ReturnID UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    OrderID UNIQUEIDENTIFIER NOT NULL,
    OrderDate DATETIME2(3) NOT NULL, -- Added to match composite FK
    ProductID UNIQUEIDENTIFIER NOT NULL,
    CustomerID UNIQUEIDENTIFIER NOT NULL,
    ReturnQuantity INT NOT NULL,
    RefundAmount DECIMAL(12,4) NOT NULL,
    ReturnReason NVARCHAR(200) NULL,
    ReturnStatus NVARCHAR(50) NOT NULL DEFAULT 'Pending',
    RestockProduct BIT NOT NULL DEFAULT 1,
    ProcessedDate DATETIME2(3) NULL,
    CreatedDate DATETIME2(3) NOT NULL DEFAULT GETUTCDATE(),
    CreatedBy NVARCHAR(50) NOT NULL DEFAULT SYSTEM_USER,
                
    CONSTRAINT FK_ProductReturn_Order FOREIGN KEY (OrderID, OrderDate) 
        REFERENCES Sales.[Order](OrderID, OrderDate),
    CONSTRAINT FK_ProductReturn_Product FOREIGN KEY (ProductID) 
        REFERENCES Inventory.Product(ProductID),
    CONSTRAINT FK_ProductReturn_Customer FOREIGN KEY (CustomerID) 
        REFERENCES Customer.Customer(CustomerID),
    CONSTRAINT CHK_ProductReturn_Quantity CHECK (ReturnQuantity > 0),
    CONSTRAINT CHK_ProductReturn_Amount CHECK (RefundAmount >= 0),
    CONSTRAINT CHK_ProductReturn_Status CHECK (ReturnStatus IN ('Pending', 'Approved', 'Rejected', 'Processed'))
);
GO

-- Create indexes for ProductReturn
CREATE NONCLUSTERED INDEX IX_ProductReturn_Order 
ON Sales.ProductReturn (OrderID, OrderDate) 
INCLUDE (ReturnStatus, CreatedDate);

CREATE NONCLUSTERED INDEX IX_ProductReturn_Customer 
ON Sales.ProductReturn (CustomerID, CreatedDate DESC);
GO

-- =============================================
-- Create Performance Optimized Indexes
-- =============================================

-- Category indexes
CREATE NONCLUSTERED INDEX IX_Category_ParentID_Active 
ON Inventory.Category (ParentCategoryID, IsActive) 
INCLUDE (CategoryName, CategoryDescription);

CREATE NONCLUSTERED INDEX IX_Category_Name 
ON Inventory.Category (CategoryName) 
WHERE IsActive = 1;

-- Product indexes
CREATE NONCLUSTERED INDEX IX_Product_Category_Active 
ON Inventory.Product (CategoryID, IsActive) 
INCLUDE (ProductName, Price, StockQuantity);

CREATE NONCLUSTERED INDEX IX_Product_SKU 
ON Inventory.Product (ProductSKU) 
WHERE IsActive = 1;

CREATE NONCLUSTERED INDEX IX_Product_Active_Stock 
ON Inventory.Product (StockQuantity, ReorderLevel)
--WHERE StockQuantity <= ReorderLevel AND IsActive = 1;

CREATE NONCLUSTERED INDEX IX_Product_Name_Search 
ON Inventory.Product (ProductName) 
WHERE IsActive = 1;

-- Customer indexes
CREATE NONCLUSTERED INDEX IX_Customer_EmailHash 
ON Customer.Customer (EmailHash) 
WHERE IsActive = 1;

CREATE NONCLUSTERED INDEX IX_Customer_CreatedDate 
ON Customer.Customer (CreatedDate DESC);

-- Address indexes
CREATE NONCLUSTERED INDEX IX_ShippingAddress_Customer 
ON Customer.ShippingAddress (CustomerID, IsDefault DESC, IsActive) 
INCLUDE (AddressLine1, City, StateProvince, PostalCode);

CREATE NONCLUSTERED INDEX IX_BillingAddress_Customer 
ON Customer.BillingAddress (CustomerID, IsDefault DESC, IsActive) 
INCLUDE (AddressLine1, City, StateProvince, PostalCode);

-- Order indexes
CREATE NONCLUSTERED INDEX IX_Order_Customer_Date 
ON Sales.[Order] (CustomerID, OrderDate DESC) 
INCLUDE (OrderStatus, TotalAmount);

CREATE NONCLUSTERED INDEX IX_Order_Status_Date 
ON Sales.[Order] (OrderStatus, OrderDate DESC) 
INCLUDE (CustomerID, TotalAmount);

CREATE NONCLUSTERED INDEX IX_Order_Date_Status 
ON Sales.[Order] (OrderDate DESC, OrderStatus) 
INCLUDE (CustomerID, TotalAmount);

-- OrderDetail indexes
CREATE NONCLUSTERED INDEX IX_OrderDetail_Order 
ON Sales.OrderDetail (OrderID) 
INCLUDE (ProductID, Quantity, UnitPrice, LineTotal);

CREATE NONCLUSTERED INDEX IX_OrderDetail_Product 
ON Sales.OrderDetail (ProductID) 
INCLUDE (OrderID, Quantity, UnitPrice);

-- Inventory transaction indexes
CREATE NONCLUSTERED INDEX IX_InventoryTransaction_Product_Date 
ON Inventory.InventoryTransaction (ProductID, TransactionDate DESC) 
INCLUDE (TransactionType, Quantity, NewStock);

CREATE NONCLUSTERED INDEX IX_InventoryTransaction_Reference 
ON Inventory.InventoryTransaction (ReferenceID, ReferenceType) 
INCLUDE (ProductID, Quantity, TransactionDate);

-- Audit log indexes
CREATE NONCLUSTERED INDEX IX_AuditLog_Table_Date 
ON Security.AuditLog (TableName, ChangedDate DESC) 
INCLUDE (Operation, ChangedBy);

CREATE NONCLUSTERED INDEX IX_AuditLog_PrimaryKey 
ON Security.AuditLog (TableName, PrimaryKeyValue) 
INCLUDE (Operation, ChangedDate, ChangedBy);

GO

PRINT 'Database schema created successfully with optimized indexes for high-performance operations.';
GO