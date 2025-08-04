-- =============================================
-- E-Commerce Stored Procedures
-- High-Performance Business Logic Implementation
-- =============================================

USE ECommerceDB;
GO

-- =============================================
-- Stored Procedure: Process Order
-- Handles order creation, inventory updates, and confirmations
-- =============================================
CREATE OR ALTER PROCEDURE Sales.ProcessOrder
    @CustomerID UNIQUEIDENTIFIER,
    @ShippingAddressID INT = NULL,
    @BillingAddressID INT = NULL,
    @ShippingMethod NVARCHAR(50) = 'Standard',
    @OrderItems NVARCHAR(MAX), -- JSON format: [{"ProductID":"xxx","Quantity":1,"UnitPrice":10.99}]
    @TaxRate DECIMAL(5,4) = 0.0875, -- 8.75% default tax rate
    @ShippingAmount DECIMAL(12,4) = 0,
    @DiscountAmount DECIMAL(12,4) = 0,
    @OrderID UNIQUEIDENTIFIER OUTPUT,
    @TotalAmount DECIMAL(12,4) OUTPUT,
    @ErrorMessage NVARCHAR(500) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @TransactionStarted BIT = 0;
    DECLARE @SubTotal DECIMAL(12,4) = 0;
    DECLARE @TaxAmount DECIMAL(12,4) = 0;
    DECLARE @OrderDate DATETIME2(3) = GETUTCDATE();
    
    BEGIN TRY
        -- Start transaction
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @TransactionStarted = 1;
        END
        
        -- Generate new order ID
        SET @OrderID = NEWID();
        
        -- Validate customer exists and is active
        IF NOT EXISTS (SELECT 1 FROM Customer.Customer WHERE CustomerID = @CustomerID AND IsActive = 1)
        BEGIN
            SET @ErrorMessage = 'Customer not found or inactive.';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        -- Create temp table for order items
        CREATE TABLE #OrderItems (
            ProductID UNIQUEIDENTIFIER,
            Quantity INT,
            UnitPrice DECIMAL(12,4),
            LineTotal DECIMAL(12,4),
            AvailableStock INT
        );
        
        -- Parse JSON order items
        INSERT INTO #OrderItems (ProductID, Quantity, UnitPrice)
        SELECT 
            CAST(JSON_VALUE(value, '$.ProductID') AS UNIQUEIDENTIFIER),
            CAST(JSON_VALUE(value, '$.Quantity') AS INT),
            CAST(JSON_VALUE(value, '$.UnitPrice') AS DECIMAL(12,4))
        FROM OPENJSON(@OrderItems);
        
        -- Validate and get current stock levels
        UPDATE oi
        SET AvailableStock = p.StockQuantity,
            LineTotal = oi.Quantity * oi.UnitPrice
        FROM #OrderItems oi
        INNER JOIN Inventory.Product p ON oi.ProductID = p.ProductID
        WHERE p.IsActive = 1;
        
        -- Check for invalid products
        IF EXISTS (SELECT 1 FROM #OrderItems WHERE AvailableStock IS NULL)
        BEGIN
            SET @ErrorMessage = 'One or more products are invalid or inactive.';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        -- Check inventory availability
        IF EXISTS (SELECT 1 FROM #OrderItems WHERE Quantity > AvailableStock)
        BEGIN
            SET @ErrorMessage = 'Insufficient inventory for one or more products.';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        -- Calculate subtotal
        SELECT @SubTotal = SUM(LineTotal) FROM #OrderItems;
        
        -- Calculate tax
        SET @TaxAmount = @SubTotal * @TaxRate;
        
        -- Calculate total
        SET @TotalAmount = @SubTotal + @TaxAmount + @ShippingAmount - @DiscountAmount;
        
        -- Validate addresses if provided
        IF @ShippingAddressID IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM Customer.ShippingAddress 
            WHERE ShippingAddressID = @ShippingAddressID 
            AND CustomerID = @CustomerID 
            AND IsActive = 1
        )
        BEGIN
            SET @ErrorMessage = 'Invalid shipping address.';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        IF @BillingAddressID IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM Customer.BillingAddress 
            WHERE BillingAddressID = @BillingAddressID 
            AND CustomerID = @CustomerID 
            AND IsActive = 1
        )
        BEGIN
            SET @ErrorMessage = 'Invalid billing address.';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        -- Create the order
        INSERT INTO Sales.[Order] (
            OrderID, CustomerID, OrderDate, OrderStatus,
            ShippingAddressID, BillingAddressID,
            SubTotal, TaxAmount, ShippingAmount, DiscountAmount, TotalAmount,
            PaymentStatus, ShippingMethod
        )
        VALUES (
            @OrderID, @CustomerID, @OrderDate, 'Pending',
            @ShippingAddressID, @BillingAddressID,
            @SubTotal, @TaxAmount, @ShippingAmount, @DiscountAmount, @TotalAmount,
            'Pending', @ShippingMethod
        );
        
        -- Create order details and update inventory
        INSERT INTO Sales.OrderDetail (OrderID, ProductID, Quantity, UnitPrice, DiscountAmount)
        SELECT @OrderID, ProductID, Quantity, UnitPrice, 0
        FROM #OrderItems;
        
        -- Update product inventory with row-level locking
        UPDATE p
        SET StockQuantity = p.StockQuantity - oi.Quantity,
            ModifiedDate = GETUTCDATE()
        FROM Inventory.Product p WITH (ROWLOCK)
        INNER JOIN #OrderItems oi ON p.ProductID = oi.ProductID;
        
        -- Log inventory transactions
        INSERT INTO Inventory.InventoryTransaction (
            ProductID, TransactionType, Quantity, PreviousStock, NewStock,
            ReferenceID, ReferenceType, Notes
        )
        SELECT 
            oi.ProductID, 
            'Sale', 
            -oi.Quantity,
            oi.AvailableStock,
            oi.AvailableStock - oi.Quantity,
            @OrderID,
            'Order',
            'Order processing - OrderID: ' + CAST(@OrderID AS NVARCHAR(50))
        FROM #OrderItems oi;
        
        -- Commit transaction
        IF @TransactionStarted = 1
            COMMIT TRANSACTION;
        
        -- Return success
        SET @ErrorMessage = NULL;
        
        -- Clean up
        DROP TABLE #OrderItems;
        
    END TRY
    BEGIN CATCH
        -- Rollback transaction on error
        IF @TransactionStarted = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @OrderID = NULL;
        SET @TotalAmount = 0;
        
        -- Clean up
        IF OBJECT_ID('tempdb..#OrderItems') IS NOT NULL
            DROP TABLE #OrderItems;
        
        -- Re-raise the error
        THROW;
    END CATCH
END;
GO

-- =============================================
-- Stored Procedure: Sales Report by Category and Product
-- Generates comprehensive sales analytics
-- =============================================
CREATE OR ALTER PROCEDURE Sales.GetSalesReport
    @StartDate DATETIME2(3) = NULL,
    @EndDate DATETIME2(3) = NULL,
    @CategoryID INT = NULL,
    @ProductID UNIQUEIDENTIFIER = NULL,
    @ReportType NVARCHAR(20) = 'Summary' -- 'Summary', 'Detailed', 'Category', 'Product'
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Set default date range if not provided (last 30 days)
    IF @StartDate IS NULL
        SET @StartDate = DATEADD(DAY, -30, GETUTCDATE());
    
    IF @EndDate IS NULL
        SET @EndDate = GETUTCDATE();
    
    -- Validate date range
    IF @StartDate > @EndDate
    BEGIN
        RAISERROR('Start date cannot be greater than end date.', 16, 1);
        RETURN;
    END
    
    -- Summary Report
    IF @ReportType = 'Summary'
    BEGIN
        SELECT 
            'Sales Summary' AS ReportType,
            @StartDate AS StartDate,
            @EndDate AS EndDate,
            COUNT(DISTINCT o.OrderID) AS TotalOrders,
            COUNT(DISTINCT o.CustomerID) AS UniqueCustomers,
            SUM(o.TotalAmount) AS TotalRevenue,
            SUM(o.SubTotal) AS TotalSubTotal,
            SUM(o.TaxAmount) AS TotalTax,
            SUM(o.ShippingAmount) AS TotalShipping,
            SUM(o.DiscountAmount) AS TotalDiscounts,
            AVG(o.TotalAmount) AS AverageOrderValue,
            SUM(od.Quantity) AS TotalItemsSold
        FROM Sales.[Order] o WITH (NOLOCK)
        INNER JOIN Sales.OrderDetail od WITH (NOLOCK) ON o.OrderID = od.OrderID
        WHERE o.OrderDate >= @StartDate 
        AND o.OrderDate <= @EndDate
        AND o.OrderStatus NOT IN ('Cancelled');
    END
    
    -- Category Report
    IF @ReportType = 'Category' OR @ReportType = 'Detailed'
    BEGIN
        SELECT 
            c.CategoryID,
            c.CategoryName,
            c.CategoryDescription,
            COUNT(DISTINCT o.OrderID) AS OrderCount,
            SUM(od.Quantity) AS QuantitySold,
            SUM(od.LineTotal) AS TotalRevenue,
            AVG(od.UnitPrice) AS AveragePrice,
            COUNT(DISTINCT p.ProductID) AS ProductsInCategory,
            MIN(o.OrderDate) AS FirstSaleDate,
            MAX(o.OrderDate) AS LastSaleDate
        FROM Inventory.Category c
        INNER JOIN Inventory.Product p ON c.CategoryID = p.CategoryID
        INNER JOIN Sales.OrderDetail od ON p.ProductID = od.ProductID
        INNER JOIN Sales.[Order] o ON od.OrderID = o.OrderID
        WHERE o.OrderDate >= @StartDate 
        AND o.OrderDate <= @EndDate
        AND o.OrderStatus NOT IN ('Cancelled')
        AND (@CategoryID IS NULL OR c.CategoryID = @CategoryID)
        GROUP BY c.CategoryID, c.CategoryName, c.CategoryDescription
        ORDER BY TotalRevenue DESC;
    END
    
    -- Product Report
    IF @ReportType = 'Product' OR @ReportType = 'Detailed'
    BEGIN
        SELECT 
            p.ProductID,
            p.ProductName,
            p.ProductSKU,
            c.CategoryName,
            p.Price AS CurrentPrice,
            AVG(od.UnitPrice) AS AverageSoldPrice,
            SUM(od.Quantity) AS QuantitySold,
            SUM(od.LineTotal) AS TotalRevenue,
            COUNT(DISTINCT od.OrderID) AS OrderCount,
            p.StockQuantity AS CurrentStock,
            CASE 
                WHEN p.StockQuantity <= p.ReorderLevel THEN 'Low Stock'
                WHEN p.StockQuantity = 0 THEN 'Out of Stock'
                ELSE 'In Stock'
            END AS StockStatus,
            MIN(o.OrderDate) AS FirstSaleDate,
            MAX(o.OrderDate) AS LastSaleDate
        FROM Inventory.Product p
        INNER JOIN Inventory.Category c ON p.CategoryID = c.CategoryID
        INNER JOIN Sales.OrderDetail od ON p.ProductID = od.ProductID
        INNER JOIN Sales.[Order] o ON od.OrderID = o.OrderID
        WHERE o.OrderDate >= @StartDate 
        AND o.OrderDate <= @EndDate
        AND o.OrderStatus NOT IN ('Cancelled')
        AND (@CategoryID IS NULL OR c.CategoryID = @CategoryID)
        AND (@ProductID IS NULL OR p.ProductID = @ProductID)
        GROUP BY 
            p.ProductID, p.ProductName, p.ProductSKU, c.CategoryName,
            p.Price, p.StockQuantity, p.ReorderLevel
        ORDER BY TotalRevenue DESC;
    END
    
    -- Performance metrics
    IF @ReportType = 'Detailed'
    BEGIN
        SELECT 
            'Performance Metrics' AS MetricType,
            DATENAME(MONTH, o.OrderDate) + ' ' + CAST(YEAR(o.OrderDate) AS NVARCHAR(4)) AS Period,
            COUNT(DISTINCT o.OrderID) AS MonthlyOrders,
            SUM(o.TotalAmount) AS MonthlyRevenue,
            AVG(o.TotalAmount) AS MonthlyAOV,
            COUNT(DISTINCT o.CustomerID) AS MonthlyCustomers
        FROM Sales.[Order] o WITH (NOLOCK)
        WHERE o.OrderDate >= @StartDate 
        AND o.OrderDate <= @EndDate
        AND o.OrderStatus NOT IN ('Cancelled')
        GROUP BY YEAR(o.OrderDate), MONTH(o.OrderDate), DATENAME(MONTH, o.OrderDate)
        ORDER BY YEAR(o.OrderDate), MONTH(o.OrderDate);
    END
END;
GO

-- =============================================
-- Stored Procedure: Handle Product Returns and Refunds
-- Manages return processing, inventory updates, and refunds
-- =============================================
CREATE OR ALTER PROCEDURE Sales.ProcessReturn
    @OrderID UNIQUEIDENTIFIER,
	@OrderDate DATETIME2(3), -- Added to match composite FK
    @ProductID UNIQUEIDENTIFIER,
    @ReturnQuantity INT,
    @ReturnReason NVARCHAR(200),
    @RefundAmount DECIMAL(12,4) = NULL,
    @RestockProduct BIT = 1,
    @ReturnID UNIQUEIDENTIFIER OUTPUT,
    @ErrorMessage NVARCHAR(500) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @TransactionStarted BIT = 0;
    DECLARE @OrderDetailID UNIQUEIDENTIFIER;
    DECLARE @OriginalQuantity INT;
    DECLARE @UnitPrice DECIMAL(12,4);
    DECLARE @CurrentStock INT;
    DECLARE @OrderStatus NVARCHAR(50);
    DECLARE @CustomerID UNIQUEIDENTIFIER;
    
    BEGIN TRY
        -- Start transaction
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @TransactionStarted = 1;
        END
        
        -- Generate return ID
        SET @ReturnID = NEWID();
        
        -- Validate order and get details
        SELECT 
            @OrderDetailID = od.OrderDetailID,
            @OriginalQuantity = od.Quantity,
            @UnitPrice = od.UnitPrice,
            @OrderStatus = o.OrderStatus,
            @CustomerID = o.CustomerID
        FROM Sales.[Order] o
        INNER JOIN Sales.OrderDetail od ON o.OrderID = od.OrderID
        WHERE o.OrderID = @OrderID 
        AND od.ProductID = @ProductID;
        
        -- Validate order exists
        IF @OrderDetailID IS NULL
        BEGIN
            SET @ErrorMessage = 'Order or product not found.';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        -- Validate order status allows returns
        IF @OrderStatus NOT IN ('Delivered', 'Shipped')
        BEGIN
            SET @ErrorMessage = 'Returns are only allowed for delivered or shipped orders.';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        -- Validate return quantity
        IF @ReturnQuantity <= 0 OR @ReturnQuantity > @OriginalQuantity
        BEGIN
            SET @ErrorMessage = 'Invalid return quantity.';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        -- Calculate refund amount if not provided
        IF @RefundAmount IS NULL
            SET @RefundAmount = @ReturnQuantity * @UnitPrice;
        
        -- Get current stock level
        SELECT @CurrentStock = StockQuantity 
        FROM Inventory.Product 
        WHERE ProductID = @ProductID;
        
        -- Create return record (we'll need to create this table)
        IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'Sales.ProductReturn') AND type in (N'U'))
        BEGIN
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
            
			CREATE NONCLUSTERED INDEX IX_ProductReturn_Order 
			ON Sales.ProductReturn (OrderID, OrderDate) 
			INCLUDE (ReturnStatus, CreatedDate);
            
			CREATE NONCLUSTERED INDEX IX_ProductReturn_Customer 
			ON Sales.ProductReturn (CustomerID, CreatedDate DESC);
        END
        
        -- Insert return record
        INSERT INTO Sales.ProductReturn (
            ReturnID, OrderID, OrderDate, ProductID, CustomerID,
            ReturnQuantity, RefundAmount, ReturnReason,
            ReturnStatus, RestockProduct
        )
        VALUES (
            @ReturnID, @OrderID, @OrderDate, @ProductID, @CustomerID,
            @ReturnQuantity, @RefundAmount, @ReturnReason,
            'Approved', @RestockProduct
        );
        
        -- Update inventory if restocking
        IF @RestockProduct = 1
        BEGIN
            UPDATE Inventory.Product 
            SET StockQuantity = StockQuantity + @ReturnQuantity,
                ModifiedDate = GETUTCDATE()
            WHERE ProductID = @ProductID;
            
            -- Log inventory transaction
            INSERT INTO Inventory.InventoryTransaction (
                ProductID, TransactionType, Quantity, PreviousStock, NewStock,
                ReferenceID, ReferenceType, Notes
            )
            VALUES (
                @ProductID, 'Return', @ReturnQuantity, @CurrentStock, @CurrentStock + @ReturnQuantity,
                @ReturnID, 'Return', 'Product return - ReturnID: ' + CAST(@ReturnID AS NVARCHAR(50))
            );
        END
        
        -- Update order status if fully returned
        DECLARE @RemainingItems INT;
        SELECT @RemainingItems = COUNT(*)
        FROM Sales.OrderDetail od
        LEFT JOIN Sales.ProductReturn pr ON od.OrderID = pr.OrderID 
            AND od.ProductID = pr.ProductID 
            AND pr.ReturnStatus = 'Approved'
        WHERE od.OrderID = @OrderID
        AND (pr.ReturnID IS NULL OR od.Quantity > pr.ReturnQuantity);
        
        IF @RemainingItems = 0
        BEGIN
            UPDATE Sales.[Order]
            SET OrderStatus = 'Returned',
                ModifiedDate = GETUTCDATE()
            WHERE OrderID = @OrderID;
        END
        
        -- Mark return as processed
        UPDATE Sales.ProductReturn
        SET ReturnStatus = 'Processed',
            ProcessedDate = GETUTCDATE()
        WHERE ReturnID = @ReturnID;
        
        -- Commit transaction
        IF @TransactionStarted = 1
            COMMIT TRANSACTION;
        
        SET @ErrorMessage = NULL;
        
    END TRY
    BEGIN CATCH
        -- Rollback transaction on error
        IF @TransactionStarted = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @ReturnID = NULL;
        
        -- Re-raise the error
        THROW;
    END CATCH
END;
GO

-- =============================================
-- Stored Procedure: Update Product Inventory
-- Handles inventory adjustments with audit trail
-- =============================================
CREATE OR ALTER PROCEDURE Inventory.UpdateProductInventory
    @ProductID UNIQUEIDENTIFIER,
    @AdjustmentType NVARCHAR(20), -- 'Adjustment', 'Restock', 'Damage', 'Transfer'
    @Quantity INT, -- Positive for additions, negative for reductions
    @Notes NVARCHAR(500) = NULL,
    @ReferenceID UNIQUEIDENTIFIER = NULL,
    @ErrorMessage NVARCHAR(500) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @TransactionStarted BIT = 0;
    DECLARE @CurrentStock INT;
    DECLARE @NewStock INT;
    
    BEGIN TRY
        -- Start transaction
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @TransactionStarted = 1;
        END
        
        -- Get current stock with row lock
        SELECT @CurrentStock = StockQuantity
        FROM Inventory.Product WITH (ROWLOCK)
        WHERE ProductID = @ProductID AND IsActive = 1;
        
        -- Validate product exists
        IF @CurrentStock IS NULL
        BEGIN
            SET @ErrorMessage = 'Product not found or inactive.';
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        -- Calculate new stock level
        SET @NewStock = @CurrentStock + @Quantity;
        
        -- Validate new stock level
        IF @NewStock < 0
        BEGIN
            SET @ErrorMessage = 'Insufficient inventory. Current stock: ' + CAST(@CurrentStock AS NVARCHAR(10));
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN;
        END
        
        -- Update product inventory
        UPDATE Inventory.Product
        SET StockQuantity = @NewStock,
            ModifiedDate = GETUTCDATE()
        WHERE ProductID = @ProductID;
        
        -- Log inventory transaction
        INSERT INTO Inventory.InventoryTransaction (
            ProductID, TransactionType, Quantity, PreviousStock, NewStock,
            ReferenceID, ReferenceType, Notes
        )
        VALUES (
            @ProductID, @AdjustmentType, @Quantity, @CurrentStock, @NewStock,
            @ReferenceID, 'Manual', ISNULL(@Notes, 'Manual inventory adjustment')
        );
        
        -- Commit transaction
        IF @TransactionStarted = 1
            COMMIT TRANSACTION;
        
        SET @ErrorMessage = NULL;
        
    END TRY
    BEGIN CATCH
        -- Rollback transaction on error
        IF @TransactionStarted = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SET @ErrorMessage = ERROR_MESSAGE();
        
        -- Re-raise the error
        THROW;
    END CATCH
END;
GO

-- =============================================
-- Stored Procedure: Get Low Stock Products
-- Returns products that need restocking
-- =============================================
CREATE OR ALTER PROCEDURE Inventory.GetLowStockProducts
    @CategoryID INT = NULL,
    @IncludeOutOfStock BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        p.ProductID,
        p.ProductName,
        p.ProductSKU,
        c.CategoryName,
        p.StockQuantity,
        p.ReorderLevel,
        p.Price,
        CASE 
            WHEN p.StockQuantity = 0 THEN 'Out of Stock'
            WHEN p.StockQuantity <= p.ReorderLevel THEN 'Low Stock'
            ELSE 'In Stock'
        END AS StockStatus,
        p.ReorderLevel - p.StockQuantity AS SuggestedOrderQuantity,
        p.ModifiedDate AS LastStockUpdate,
        -- Get recent sales velocity (last 30 days)
        ISNULL(sales.QuantitySold, 0) AS QuantitySoldLast30Days,
        CASE 
            WHEN ISNULL(sales.QuantitySold, 0) > 0 
            THEN CAST(p.StockQuantity AS FLOAT) / (ISNULL(sales.QuantitySold, 0) / 30.0)
            ELSE 999
        END AS DaysOfInventoryRemaining
    FROM Inventory.Product p
    INNER JOIN Inventory.Category c ON p.CategoryID = c.CategoryID
    LEFT JOIN (
        SELECT 
            od.ProductID,
            SUM(od.Quantity) AS QuantitySold
        FROM Sales.OrderDetail od
        INNER JOIN Sales.[Order] o ON od.OrderID = o.OrderID
        WHERE o.OrderDate >= DATEADD(DAY, -30, GETUTCDATE())
        AND o.OrderStatus NOT IN ('Cancelled')
        GROUP BY od.ProductID
    ) sales ON p.ProductID = sales.ProductID
    WHERE p.IsActive = 1
    AND (
        (@IncludeOutOfStock = 1 AND p.StockQuantity <= p.ReorderLevel)
        OR (@IncludeOutOfStock = 0 AND p.StockQuantity > 0 AND p.StockQuantity <= p.ReorderLevel)
    )
    AND (@CategoryID IS NULL OR p.CategoryID = @CategoryID)
    ORDER BY 
        CASE WHEN p.StockQuantity = 0 THEN 0 ELSE 1 END, -- Out of stock first
        DaysOfInventoryRemaining,
        p.StockQuantity;
END;
GO

PRINT 'Stored procedures created successfully.';
GO