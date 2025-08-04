-- =============================================
-- E-Commerce Triggers and Data Integrity
-- Advanced data validation and audit trails
-- =============================================

USE ECommerceDB;
GO

-- =============================================
-- Trigger: Product Stock Update Validation
-- Ensures inventory levels are properly maintained
-- =============================================
CREATE OR ALTER TRIGGER tr_Product_StockValidation
ON Inventory.Product
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Check for negative stock
    IF EXISTS (SELECT 1 FROM inserted WHERE StockQuantity < 0)
    BEGIN
        RAISERROR('Stock quantity cannot be negative.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
    
    -- Update ModifiedDate for stock changes
    UPDATE p
    SET ModifiedDate = GETUTCDATE()
    FROM Inventory.Product p
    INNER JOIN inserted i ON p.ProductID = i.ProductID
    INNER JOIN deleted d ON p.ProductID = d.ProductID
    WHERE i.StockQuantity != d.StockQuantity;
    
    -- Create low stock alerts for products below reorder level
    INSERT INTO Security.AuditLog (TableName, Operation, PrimaryKeyValue, OldValues, NewValues, ChangedBy)
    SELECT 
        'Product',
        'STOCK_ALERT',
        CAST(i.ProductID AS NVARCHAR(50)),
        'Stock: ' + CAST(d.StockQuantity AS NVARCHAR(10)),
        'Stock: ' + CAST(i.StockQuantity AS NVARCHAR(10)) + ' (Below Reorder Level: ' + CAST(i.ReorderLevel AS NVARCHAR(10)) + ')',
        SYSTEM_USER
    FROM inserted i
    INNER JOIN deleted d ON i.ProductID = d.ProductID
    WHERE i.StockQuantity <= i.ReorderLevel 
    AND d.StockQuantity > d.ReorderLevel;
END;
GO

-- =============================================
-- Trigger: Order Total Calculation
-- Automatically calculates order totals when order details change
-- =============================================
CREATE OR ALTER TRIGGER tr_OrderDetail_UpdateOrderTotals
ON Sales.OrderDetail
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @AffectedOrders TABLE (OrderID UNIQUEIDENTIFIER);
    
    -- Get affected orders
    INSERT INTO @AffectedOrders (OrderID)
    SELECT DISTINCT OrderID FROM inserted
    UNION
    SELECT DISTINCT OrderID FROM deleted;
    
    -- Update order totals
    UPDATE o
    SET 
        SubTotal = ISNULL(od.SubTotal, 0),
        TotalAmount = ISNULL(od.SubTotal, 0) + o.TaxAmount + o.ShippingAmount - o.DiscountAmount,
        ModifiedDate = GETUTCDATE()
    FROM Sales.[Order] o
    INNER JOIN @AffectedOrders ao ON o.OrderID = ao.OrderID
    LEFT JOIN (
        SELECT 
            OrderID,
            SUM(LineTotal) AS SubTotal
        FROM Sales.OrderDetail
        GROUP BY OrderID
    ) od ON o.OrderID = od.OrderID;
    
    -- Recalculate tax if needed (assuming tax is percentage of subtotal)
    UPDATE o
    SET 
        TaxAmount = SubTotal * 0.0875, -- Default 8.75% tax rate
        TotalAmount = SubTotal + (SubTotal * 0.0875) + ShippingAmount - DiscountAmount
    FROM Sales.[Order] o
    INNER JOIN @AffectedOrders ao ON o.OrderID = ao.OrderID
    WHERE o.TaxAmount = 0 OR o.TaxAmount IS NULL;
END;
GO

-- =============================================
-- Trigger: Customer Data Encryption
-- Encrypts sensitive customer data on insert/update
-- =============================================
CREATE OR ALTER TRIGGER tr_Customer_EncryptData
ON Customer.Customer
INSTEAD OF INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Open symmetric key for encryption
    OPEN SYMMETRIC KEY ECommerceSymmetricKey
    DECRYPTION BY CERTIFICATE ECommerceCert;
    
    -- Handle INSERT
    IF NOT EXISTS (SELECT * FROM deleted)
    BEGIN
        INSERT INTO Customer.Customer (
            CustomerID, CustomerName, Email, PhoneNumber,
            Address, ShippingAddress, BillingAddress,
            IsActive, CreatedDate, ModifiedDate
        )
        SELECT 
            ISNULL(i.CustomerID, NEWID()),
            i.CustomerName,
            CASE 
                WHEN i.Email IS NOT NULL THEN EncryptByKey(Key_GUID('ECommerceSymmetricKey'), i.Email)
                ELSE NULL
            END,
            CASE 
                WHEN i.PhoneNumber IS NOT NULL THEN EncryptByKey(Key_GUID('ECommerceSymmetricKey'), i.PhoneNumber)
                ELSE NULL
            END,
            i.Address,
            i.ShippingAddress,
            i.BillingAddress,
            ISNULL(i.IsActive, 1),
            ISNULL(i.CreatedDate, GETUTCDATE()),
            GETUTCDATE()
        FROM inserted i;
    END
    -- Handle UPDATE
    ELSE
    BEGIN
        UPDATE c
        SET 
            CustomerName = i.CustomerName,
            Email = CASE 
                WHEN i.Email IS NOT NULL THEN EncryptByKey(Key_GUID('ECommerceSymmetricKey'), i.Email)
                ELSE c.Email
            END,
            PhoneNumber = CASE 
                WHEN i.PhoneNumber IS NOT NULL THEN EncryptByKey(Key_GUID('ECommerceSymmetricKey'), i.PhoneNumber)
                ELSE c.PhoneNumber
            END,
            Address = ISNULL(i.Address, c.Address),
            ShippingAddress = ISNULL(i.ShippingAddress, c.ShippingAddress),
            BillingAddress = ISNULL(i.BillingAddress, c.BillingAddress),
            IsActive = ISNULL(i.IsActive, c.IsActive),
            ModifiedDate = GETUTCDATE()
        FROM Customer.Customer c
        INNER JOIN inserted i ON c.CustomerID = i.CustomerID;
    END
    
    -- Close symmetric key
    CLOSE SYMMETRIC KEY ECommerceSymmetricKey;
END;
GO

-- =============================================
-- Trigger: Comprehensive Audit Trail
-- Logs all changes to critical tables
-- =============================================
CREATE OR ALTER TRIGGER tr_Order_AuditTrail
ON Sales.[Order]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Operation NVARCHAR(10);
    
    -- Determine operation type
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted)
        SET @Operation = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted)
        SET @Operation = 'INSERT';
    ELSE
        SET @Operation = 'DELETE';
    
    -- Log INSERT operations
    IF @Operation = 'INSERT'
    BEGIN
        INSERT INTO Security.AuditLog (TableName, Operation, PrimaryKeyValue, NewValues)
        SELECT 
            'Order',
            'INSERT',
            CAST(i.OrderID AS NVARCHAR(50)),
            'CustomerID=' + CAST(i.CustomerID AS NVARCHAR(50)) + 
            ', TotalAmount=' + CAST(i.TotalAmount AS NVARCHAR(20)) + 
            ', OrderStatus=' + i.OrderStatus
        FROM inserted i;
    END
    
    -- Log UPDATE operations
    IF @Operation = 'UPDATE'
    BEGIN
        INSERT INTO Security.AuditLog (TableName, Operation, PrimaryKeyValue, OldValues, NewValues)
        SELECT 
            'Order',
            'UPDATE',
            CAST(i.OrderID AS NVARCHAR(50)),
            'OrderStatus=' + d.OrderStatus + ', TotalAmount=' + CAST(d.TotalAmount AS NVARCHAR(20)),
            'OrderStatus=' + i.OrderStatus + ', TotalAmount=' + CAST(i.TotalAmount AS NVARCHAR(20))
        FROM inserted i
        INNER JOIN deleted d ON i.OrderID = d.OrderID
        WHERE i.OrderStatus != d.OrderStatus OR i.TotalAmount != d.TotalAmount;
    END
    
    -- Log DELETE operations
    IF @Operation = 'DELETE'
    BEGIN
        INSERT INTO Security.AuditLog (TableName, Operation, PrimaryKeyValue, OldValues)
        SELECT 
            'Order',
            'DELETE',
            CAST(d.OrderID AS NVARCHAR(50)),
            'CustomerID=' + CAST(d.CustomerID AS NVARCHAR(50)) + 
            ', TotalAmount=' + CAST(d.TotalAmount AS NVARCHAR(20)) + 
            ', OrderStatus=' + d.OrderStatus
        FROM deleted d;
    END
END;
GO

-- =============================================
-- Trigger: Product Audit Trail
-- Tracks all product changes including price and inventory
-- =============================================
CREATE OR ALTER TRIGGER tr_Product_AuditTrail
ON Inventory.Product
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Log significant product changes
    INSERT INTO Security.AuditLog (TableName, Operation, PrimaryKeyValue, OldValues, NewValues)
    SELECT 
        'Product',
        'UPDATE',
        CAST(i.ProductID AS NVARCHAR(50)),
        'Price=' + CAST(d.Price AS NVARCHAR(20)) + ', Stock=' + CAST(d.StockQuantity AS NVARCHAR(10)),
        'Price=' + CAST(i.Price AS NVARCHAR(20)) + ', Stock=' + CAST(i.StockQuantity AS NVARCHAR(10))
    FROM inserted i
    INNER JOIN deleted d ON i.ProductID = d.ProductID
    WHERE i.Price != d.Price OR i.StockQuantity != d.StockQuantity;
END;
GO

-- =============================================
-- Trigger: Inventory Transaction Validation
-- Ensures inventory transactions are valid and consistent
-- =============================================
CREATE OR ALTER TRIGGER tr_InventoryTransaction_Validation
ON Inventory.InventoryTransaction
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Validate that the new stock matches the actual product stock
    IF EXISTS (
        SELECT 1 
        FROM inserted i
        INNER JOIN Inventory.Product p ON i.ProductID = p.ProductID
        WHERE i.NewStock != p.StockQuantity
    )
    BEGIN
        RAISERROR('Inventory transaction new stock does not match actual product stock.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
    
    -- Validate transaction logic
    IF EXISTS (
        SELECT 1 
        FROM inserted i
        WHERE i.PreviousStock + i.Quantity != i.NewStock
    )
    BEGIN
        RAISERROR('Invalid inventory transaction: PreviousStock + Quantity must equal NewStock.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- =============================================
-- Trigger: Customer Address Validation
-- Ensures only one default address per customer per type
-- =============================================
CREATE OR ALTER TRIGGER tr_ShippingAddress_DefaultValidation
ON Customer.ShippingAddress
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Reset other default addresses when a new default is set
    UPDATE sa
    SET IsDefault = 0
    FROM Customer.ShippingAddress sa
    INNER JOIN inserted i ON sa.CustomerID = i.CustomerID
    WHERE sa.ShippingAddressID != i.ShippingAddressID
    AND i.IsDefault = 1
    AND sa.IsDefault = 1;
END;
GO

CREATE OR ALTER TRIGGER tr_BillingAddress_DefaultValidation
ON Customer.BillingAddress
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Reset other default addresses when a new default is set
    UPDATE ba
    SET IsDefault = 0
    FROM Customer.BillingAddress ba
    INNER JOIN inserted i ON ba.CustomerID = i.CustomerID
    WHERE ba.BillingAddressID != i.BillingAddressID
    AND i.IsDefault = 1
    AND ba.IsDefault = 1;
END;
GO

-- =============================================
-- Additional Check Constraints
-- Business rule enforcement at the database level
-- =============================================

-- Ensure order dates are logical
ALTER TABLE Sales.[Order]
ADD CONSTRAINT CHK_Order_DateLogic 
CHECK (
    ExpectedDeliveryDate IS NULL OR 
    ExpectedDeliveryDate > OrderDate
);

-- Product price must be positive
ALTER TABLE Inventory.Product
ADD CONSTRAINT CHK_Product_PositivePrice 
CHECK (Price > 0);

-- Order detail quantity must be positive
ALTER TABLE Sales.OrderDetail
ADD CONSTRAINT CHK_OrderDetail_PositiveQuantity 
CHECK (Quantity > 0);

-- Category hierarchy constraint (prevent cycles)
ALTER TABLE Inventory.Category
ADD CONSTRAINT CHK_Category_NoSelfReference 
CHECK (CategoryID != ParentCategoryID);

/*-- Product SKU format validation (alphanumeric with dashes)
ALTER TABLE Inventory.Product
ADD CONSTRAINT CHK_Product_SKUFormat
CHECK (ProductSKU LIKE '[A-Z0-9a-z][A-Z0-9a-z-]*[A-Z0-9a-z]' OR LEN(ProductSKU) = 1);*/

-- Phone number format validation (basic US format)
-- Note: This is applied after decryption in application layer due to encryption

-- Order status transition validation
ALTER TABLE Sales.[Order]
ADD CONSTRAINT CHK_Order_ValidStatus 
CHECK (OrderStatus IN ('Pending', 'Processing', 'Shipped', 'Delivered', 'Cancelled', 'Returned'));

-- Payment status validation
ALTER TABLE Sales.[Order]
ADD CONSTRAINT CHK_Order_ValidPaymentStatus 
CHECK (PaymentStatus IN ('Pending', 'Authorized', 'Captured', 'Failed', 'Refunded'));
GO

-- =============================================
-- Stored Procedure: Data Integrity Check
-- Comprehensive database health and integrity validation
-- =============================================
CREATE OR ALTER PROCEDURE Security.CheckDataIntegrity
    @FixIssues BIT = 0, -- Set to 1 to automatically fix minor issues
    @Verbose BIT = 1    -- Set to 1 for detailed output
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @IssueCount INT = 0;
    DECLARE @Message NVARCHAR(500);
    
    CREATE TABLE #IntegrityIssues (
        IssueID INT IDENTITY(1,1),
        Severity NVARCHAR(10), -- 'Critical', 'Warning', 'Info'
        TableName NVARCHAR(50),
        IssueDescription NVARCHAR(500),
        RecordCount INT,
        FixApplied BIT DEFAULT 0
    );
    
    -- Check for orphaned order details
    INSERT INTO #IntegrityIssues (Severity, TableName, IssueDescription, RecordCount)
    SELECT 
        'Critical',
        'OrderDetail',
        'Order details without corresponding orders',
        COUNT(*)
    FROM Sales.OrderDetail od
    LEFT JOIN Sales.[Order] o ON od.OrderID = o.OrderID
    WHERE o.OrderID IS NULL
    HAVING COUNT(*) > 0;
    
    -- Check for orders without order details
    INSERT INTO #IntegrityIssues (Severity, TableName, IssueDescription, RecordCount)
    SELECT 
        'Warning',
        'Order',
        'Orders without order details',
        COUNT(*)
    FROM Sales.[Order] o
    LEFT JOIN Sales.OrderDetail od ON o.OrderID = od.OrderID
    WHERE od.OrderID IS NULL
    AND o.OrderStatus NOT IN ('Cancelled')
    HAVING COUNT(*) > 0;
    
    -- Check for negative inventory
    INSERT INTO #IntegrityIssues (Severity, TableName, IssueDescription, RecordCount)
    SELECT 
        'Critical',
        'Product',
        'Products with negative inventory',
        COUNT(*)
    FROM Inventory.Product
    WHERE StockQuantity < 0
    HAVING COUNT(*) > 0;
    
    -- Check for products without categories
    INSERT INTO #IntegrityIssues (Severity, TableName, IssueDescription, RecordCount)
    SELECT 
        'Critical',
        'Product',
        'Products without valid categories',
        COUNT(*)
    FROM Inventory.Product p
    LEFT JOIN Inventory.Category c ON p.CategoryID = c.CategoryID
    WHERE c.CategoryID IS NULL
    HAVING COUNT(*) > 0;
    
    -- Check for order total inconsistencies
    INSERT INTO #IntegrityIssues (Severity, TableName, IssueDescription, RecordCount)
    SELECT 
        'Warning',
        'Order',
        'Orders with incorrect total calculations',
        COUNT(*)
    FROM Sales.[Order] o
    INNER JOIN (
        SELECT 
            OrderID,
            SUM(LineTotal) AS CalculatedSubTotal
        FROM Sales.OrderDetail
        GROUP BY OrderID
    ) calc ON o.OrderID = calc.OrderID
    WHERE ABS(o.SubTotal - calc.CalculatedSubTotal) > 0.01
    HAVING COUNT(*) > 0;
    
    -- Check for customers without addresses
    INSERT INTO #IntegrityIssues (Severity, TableName, IssueDescription, RecordCount)
    SELECT 
        'Info',
        'Customer',
        'Active customers without shipping addresses',
        COUNT(*)
    FROM Customer.Customer c
    LEFT JOIN Customer.ShippingAddress sa ON c.CustomerID = sa.CustomerID AND sa.IsActive = 1
    WHERE c.IsActive = 1 AND sa.CustomerID IS NULL
    HAVING COUNT(*) > 0;
    
    -- Check for inventory transaction inconsistencies
    INSERT INTO #IntegrityIssues (Severity, TableName, IssueDescription, RecordCount)
    SELECT 
        'Warning',
        'InventoryTransaction',
        'Inventory transactions with calculation errors',
        COUNT(*)
    FROM Inventory.InventoryTransaction
    WHERE PreviousStock + Quantity != NewStock
    HAVING COUNT(*) > 0;
    
    -- Fix issues if requested
    IF @FixIssues = 1
    BEGIN
        -- Fix order total inconsistencies
        UPDATE o
        SET SubTotal = calc.CalculatedSubTotal,
            TotalAmount = calc.CalculatedSubTotal + o.TaxAmount + o.ShippingAmount - o.DiscountAmount,
            ModifiedDate = GETUTCDATE()
        FROM Sales.[Order] o
        INNER JOIN (
            SELECT 
                OrderID,
                SUM(LineTotal) AS CalculatedSubTotal
            FROM Sales.OrderDetail
            GROUP BY OrderID
        ) calc ON o.OrderID = calc.OrderID
        WHERE ABS(o.SubTotal - calc.CalculatedSubTotal) > 0.01;
        
        UPDATE #IntegrityIssues 
        SET FixApplied = 1 
        WHERE TableName = 'Order' AND IssueDescription LIKE '%incorrect total%';
        
        -- Fix negative inventory (set to 0 and log)
        UPDATE Inventory.Product 
        SET StockQuantity = 0,
            ModifiedDate = GETUTCDATE()
        WHERE StockQuantity < 0;
        
        INSERT INTO Security.AuditLog (TableName, Operation, PrimaryKeyValue, OldValues, NewValues, ChangedBy)
        SELECT 
            'Product',
            'FIX',
            CAST(ProductID AS NVARCHAR(50)),
            'NegativeStock=' + CAST(StockQuantity AS NVARCHAR(10)),
            'CorrectedStock=0',
            'INTEGRITY_CHECK'
        FROM Inventory.Product
        WHERE StockQuantity < 0;
        
        UPDATE #IntegrityIssues 
        SET FixApplied = 1 
        WHERE TableName = 'Product' AND IssueDescription LIKE '%negative inventory%';
    END
    
    -- Report results
    SELECT @IssueCount = COUNT(*) FROM #IntegrityIssues;
    
    IF @Verbose = 1
    BEGIN
        SELECT 
            Severity,
            TableName,
            IssueDescription,
            RecordCount,
            CASE WHEN FixApplied = 1 THEN 'Yes' ELSE 'No' END AS FixApplied
        FROM #IntegrityIssues
        ORDER BY 
            CASE Severity 
                WHEN 'Critical' THEN 1 
                WHEN 'Warning' THEN 2 
                WHEN 'Info' THEN 3 
            END,
            TableName;
    END
    
    -- Summary
    SET @Message = 'Data integrity check completed. Issues found: ' + CAST(@IssueCount AS NVARCHAR(10));
    IF @FixIssues = 1
        SET @Message = @Message + '. Fixes applied where possible.';
    
    PRINT @Message;
    
    DROP TABLE #IntegrityIssues;
    
    RETURN @IssueCount;
END;
GO

-- =============================================
-- Stored Procedure: Database Maintenance
-- Routine maintenance tasks for optimal performance
-- =============================================
CREATE OR ALTER PROCEDURE Security.PerformDatabaseMaintenance
    @UpdateStatistics BIT = 1,
    @RebuildIndexes BIT = 0,
    @ReorganizeIndexes BIT = 1,
    @ShrinkLog BIT = 0,
    @Verbose BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Message NVARCHAR(500);
    DECLARE @StartTime DATETIME2(3) = GETUTCDATE();
    
    -- Update statistics
    IF @UpdateStatistics = 1
    BEGIN
        IF @Verbose = 1 PRINT 'Updating statistics...';
        
        DECLARE stats_cursor CURSOR FOR
        SELECT 
            'UPDATE STATISTICS [' + SCHEMA_NAME(t.schema_id) + '].[' + t.name + '] [' + s.name + ']'
        FROM sys.stats s
        INNER JOIN sys.tables t ON s.object_id = t.object_id
        WHERE t.is_ms_shipped = 0;
        
        OPEN stats_cursor;
        FETCH NEXT FROM stats_cursor INTO @SQL;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sp_executesql @SQL;
            FETCH NEXT FROM stats_cursor INTO @SQL;
        END
        
        CLOSE stats_cursor;
        DEALLOCATE stats_cursor;
        
        IF @Verbose = 1 PRINT 'Statistics updated successfully.';
    END
    
    -- Reorganize indexes
    IF @ReorganizeIndexes = 1
    BEGIN
        IF @Verbose = 1 PRINT 'Reorganizing fragmented indexes...';
        
        DECLARE index_cursor CURSOR FOR
        SELECT 
            'ALTER INDEX [' + i.name + '] ON [' + SCHEMA_NAME(t.schema_id) + '].[' + t.name + '] REORGANIZE'
        FROM sys.indexes i
        INNER JOIN sys.tables t ON i.object_id = t.object_id
        INNER JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') ps 
            ON i.object_id = ps.object_id AND i.index_id = ps.index_id
        WHERE ps.avg_fragmentation_in_percent > 10
        AND ps.avg_fragmentation_in_percent < 30
        AND i.name IS NOT NULL
        AND t.is_ms_shipped = 0;
        
        OPEN index_cursor;
        FETCH NEXT FROM index_cursor INTO @SQL;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sp_executesql @SQL;
            FETCH NEXT FROM index_cursor INTO @SQL;
        END
        
        CLOSE index_cursor;
        DEALLOCATE index_cursor;
        
        IF @Verbose = 1 PRINT 'Index reorganization completed.';
    END
    
    -- Rebuild heavily fragmented indexes
    IF @RebuildIndexes = 1
    BEGIN
        IF @Verbose = 1 PRINT 'Rebuilding heavily fragmented indexes...';
        
        DECLARE rebuild_cursor CURSOR FOR
        SELECT 
            'ALTER INDEX [' + i.name + '] ON [' + SCHEMA_NAME(t.schema_id) + '].[' + t.name + '] REBUILD WITH (ONLINE = OFF)'
        FROM sys.indexes i
        INNER JOIN sys.tables t ON i.object_id = t.object_id
        INNER JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') ps 
            ON i.object_id = ps.object_id AND i.index_id = ps.index_id
        WHERE ps.avg_fragmentation_in_percent >= 30
        AND i.name IS NOT NULL
        AND t.is_ms_shipped = 0;
        
        OPEN rebuild_cursor;
        FETCH NEXT FROM rebuild_cursor INTO @SQL;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sp_executesql @SQL;
            FETCH NEXT FROM rebuild_cursor INTO @SQL;
        END
        
        CLOSE rebuild_cursor;
        DEALLOCATE rebuild_cursor;
        
        IF @Verbose = 1 PRINT 'Index rebuild completed.';
    END
    
    -- Shrink log file if requested
    IF @ShrinkLog = 1
    BEGIN
        IF @Verbose = 1 PRINT 'Shrinking transaction log...';
        DBCC SHRINKFILE('ECommerceDB_Log', 100);
        IF @Verbose = 1 PRINT 'Transaction log shrink completed.';
    END
    
    -- Final summary
    DECLARE @Duration INT = DATEDIFF(SECOND, @StartTime, GETUTCDATE());
    SET @Message = 'Database maintenance completed in ' + CAST(@Duration AS NVARCHAR(10)) + ' seconds.';
    IF @Verbose = 1 PRINT @Message;
    
    -- Log maintenance activity
    INSERT INTO Security.AuditLog (TableName, Operation, PrimaryKeyValue, NewValues, ChangedBy)
    VALUES (
        'DATABASE',
        'MAINTENANCE',
        'ECommerceDB',
        'Duration=' + CAST(@Duration AS NVARCHAR(10)) + 's, UpdateStats=' + CAST(@UpdateStatistics AS NVARCHAR(1)) + 
        ', RebuildIdx=' + CAST(@RebuildIndexes AS NVARCHAR(1)) + ', ReorgIdx=' + CAST(@ReorganizeIndexes AS NVARCHAR(1)),
        'MAINTENANCE_JOB'
    );
END;
GO

PRINT 'Triggers, constraints, and integrity procedures created successfully.';
GO