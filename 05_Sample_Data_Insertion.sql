-- =============================================
-- E-Commerce Sample Data Insertion (FIXED)
-- Realistic test data for demonstration and testing
-- =============================================

USE ECommerceDB;
GO

-- Disable triggers temporarily for bulk insert
DISABLE TRIGGER tr_Customer_EncryptData ON Customer.Customer;
GO

-- =============================================
-- Insert Categories (Hierarchical)
-- =============================================
PRINT 'Inserting categories...';

-- Root categories
INSERT INTO Inventory.Category (CategoryName, CategoryDescription, ParentCategoryID) VALUES
('Electronics', 'Electronic devices and accessories', NULL),
('Clothing', 'Apparel and fashion items', NULL),
('Home & Garden', 'Home improvement and garden supplies', NULL),
('Books', 'Books and educational materials', NULL),
('Sports & Outdoors', 'Sporting goods and outdoor equipment', NULL);

-- Sub-categories
INSERT INTO Inventory.Category (CategoryName, CategoryDescription, ParentCategoryID) VALUES
('Smartphones', 'Mobile phones and accessories', 1),
('Laptops', 'Portable computers and accessories', 1),
('Audio', 'Headphones, speakers, and audio equipment', 1),
('Men''s Clothing', 'Men''s apparel and accessories', 2),
('Women''s Clothing', 'Women''s apparel and accessories', 2),
('Kitchen', 'Kitchen appliances and cookware', 3),
('Furniture', 'Home furniture and decor', 3),
('Fiction', 'Fiction books and novels', 4),
('Non-Fiction', 'Educational and reference books', 4),
('Fitness', 'Exercise equipment and accessories', 5);

-- =============================================
-- Insert Products
-- =============================================
PRINT 'Inserting products...';

-- Electronics Products
INSERT INTO Inventory.Product (ProductName, CategoryID, Price, StockQuantity, ReorderLevel, ProductDescription, ProductSKU) VALUES
('iPhone 15 Pro', 6, 999.99, 50, 10, 'Latest iPhone with advanced camera system and A17 Pro chip', 'IPH15PRO-001'),
('Samsung Galaxy S24', 6, 899.99, 45, 10, 'Premium Android smartphone with AI features', 'SGS24-001'),
('MacBook Pro 14"', 7, 1999.99, 25, 5, 'Professional laptop with M3 chip and Retina display', 'MBP14-001'),
('Dell XPS 13', 7, 1299.99, 30, 8, 'Ultra-portable laptop with InfinityEdge display', 'DXPS13-001'),
('Sony WH-1000XM5', 8, 399.99, 75, 15, 'Industry-leading noise canceling headphones', 'SXMN5-001'),
('AirPods Pro', 8, 249.99, 100, 20, 'Active noise cancellation wireless earbuds', 'APPRO-001'),
('Bose QuietComfort', 8, 329.99, 60, 12, 'Premium noise-canceling headphones', 'BQCFRT-001');

-- Clothing Products
INSERT INTO Inventory.Product (ProductName, CategoryID, Price, StockQuantity, ReorderLevel, ProductDescription, ProductSKU) VALUES
('Men''s Cotton T-Shirt', 9, 19.99, 200, 50, 'Comfortable 100% cotton t-shirt in various colors', 'MCT-001'),
('Men''s Jeans', 9, 79.99, 150, 30, 'Classic fit denim jeans with stretch', 'MJ-001'),
('Men''s Dress Shirt', 9, 49.99, 100, 25, 'Professional dress shirt, wrinkle-free', 'MDS-001'),
('Women''s Blouse', 10, 39.99, 120, 30, 'Elegant silk-blend blouse for professional wear', 'WB-001'),
('Women''s Dress', 10, 89.99, 80, 20, 'Versatile midi dress suitable for various occasions', 'WD-001'),
('Women''s Leggings', 10, 29.99, 180, 40, 'High-waisted athletic leggings with moisture-wicking', 'WL-001');

-- Home & Garden Products
INSERT INTO Inventory.Product (ProductName, CategoryID, Price, StockQuantity, ReorderLevel, ProductDescription, ProductSKU) VALUES
('KitchenAid Stand Mixer', 11, 379.99, 40, 8, 'Professional 5-quart stand mixer with multiple attachments', 'KASM-001'),
('Instant Pot Duo', 11, 99.99, 85, 20, '7-in-1 electric pressure cooker with smart programs', 'IPD-001'),
('Ninja Blender', 11, 149.99, 65, 15, 'High-performance blender for smoothies and more', 'NB-001'),
('Office Chair', 12, 299.99, 55, 12, 'Ergonomic office chair with lumbar support', 'OC-001'),
('Coffee Table', 12, 199.99, 35, 8, 'Modern wooden coffee table with storage', 'CT-001'),
('Bookshelf', 12, 159.99, 45, 10, '5-tier wooden bookshelf for home organization', 'BS-001');

-- Books
INSERT INTO Inventory.Product (ProductName, CategoryID, Price, StockQuantity, ReorderLevel, ProductDescription, ProductSKU) VALUES
('The Great Gatsby', 13, 12.99, 150, 30, 'Classic American novel by F. Scott Fitzgerald', 'TGG-001'),
('To Kill a Mockingbird', 13, 13.99, 120, 25, 'Pulitzer Prize-winning novel by Harper Lee', 'TKAM-001'),
('1984', 13, 14.99, 200, 40, 'Dystopian novel by George Orwell', 'N1984-001'),
('Sapiens', 14, 16.99, 100, 20, 'A Brief History of Humankind by Yuval Noah Harari', 'SAP-001'),
('Atomic Habits', 14, 18.99, 180, 35, 'Self-help book on building good habits', 'AH-001'),
('The Psychology of Money', 14, 15.99, 90, 20, 'Financial wisdom by Morgan Housel', 'POM-001');

-- Sports & Fitness
INSERT INTO Inventory.Product (ProductName, CategoryID, Price, StockQuantity, ReorderLevel, ProductDescription, ProductSKU) VALUES
('Yoga Mat', 15, 29.99, 120, 25, 'Non-slip exercise mat for yoga and fitness', 'YM-001'),
('Dumbbell Set', 15, 149.99, 60, 12, 'Adjustable dumbbell set with multiple weights', 'DS-001'),
('Resistance Bands', 15, 19.99, 200, 40, 'Set of resistance bands for strength training', 'RB-001'),
('Running Shoes', 15, 129.99, 100, 20, 'Lightweight running shoes with cushioned sole', 'RS-001'),
('Water Bottle', 15, 24.99, 300, 60, 'Insulated stainless steel water bottle', 'WA-001');

-- =============================================
-- Insert Customers (with encrypted data via stored procedure)
-- =============================================
PRINT 'Inserting customers...';
GO

-- We need to create a procedure to handle encrypted customer insertion
CREATE OR ALTER PROCEDURE Customer.InsertSampleCustomer
    @CustomerName NVARCHAR(100),
    @Email NVARCHAR(100),
    @PhoneNumber NVARCHAR(20),
    @Address NVARCHAR(200),
    @ShippingAddress NVARCHAR(200),
    @BillingAddress NVARCHAR(200)
AS
BEGIN
    OPEN SYMMETRIC KEY ECommerceSymmetricKey
    DECRYPTION BY CERTIFICATE ECommerceCert;
    
    INSERT INTO Customer.Customer (
        CustomerName, Email, PhoneNumber, Address, ShippingAddress, BillingAddress
    ) VALUES (
        @CustomerName,
        EncryptByKey(Key_GUID('ECommerceSymmetricKey'), @Email),
        EncryptByKey(Key_GUID('ECommerceSymmetricKey'), @PhoneNumber),
        @Address,
        @ShippingAddress,
        @BillingAddress
    );
    
    CLOSE SYMMETRIC KEY ECommerceSymmetricKey;
END;
GO

-- Insert sample customers
EXEC Customer.InsertSampleCustomer 'John Smith', 'john.smith@email.com', '555-0101', '123 Main St, Anytown, ST 12345', '123 Main St, Anytown, ST 12345', '123 Main St, Anytown, ST 12345';
EXEC Customer.InsertSampleCustomer 'Sarah Johnson', 'sarah.johnson@email.com', '555-0102', '456 Oak Ave, Springfield, ST 12346', '456 Oak Ave, Springfield, ST 12346', '456 Oak Ave, Springfield, ST 12346';
EXEC Customer.InsertSampleCustomer 'Michael Brown', 'michael.brown@email.com', '555-0103', '789 Pine Rd, Riverside, ST 12347', '789 Pine Rd, Riverside, ST 12347', '789 Pine Rd, Riverside, ST 12347';
EXEC Customer.InsertSampleCustomer 'Emily Davis', 'emily.davis@email.com', '555-0104', '321 Elm St, Lakewood, ST 12348', '321 Elm St, Lakewood, ST 12348', '321 Elm St, Lakewood, ST 12348';
EXEC Customer.InsertSampleCustomer 'David Wilson', 'david.wilson@email.com', '555-0105', '654 Maple Dr, Hillside, ST 12349', '654 Maple Dr, Hillside, ST 12349', '654 Maple Dr, Hillside, ST 12349';
EXEC Customer.InsertSampleCustomer 'Lisa Anderson', 'lisa.anderson@email.com', '555-0106', '987 Cedar Ln, Brookfield, ST 12350', '987 Cedar Ln, Brookfield, ST 12350', '987 Cedar Ln, Brookfield, ST 12350';
EXEC Customer.InsertSampleCustomer 'Robert Taylor', 'robert.taylor@email.com', '555-0107', '147 Birch Way, Greenville, ST 12351', '147 Birch Way, Greenville, ST 12351', '147 Birch Way, Greenville, ST 12351';
EXEC Customer.InsertSampleCustomer 'Jennifer Martinez', 'jennifer.martinez@email.com', '555-0108', '258 Spruce Ave, Fairfield, ST 12352', '258 Spruce Ave, Fairfield, ST 12352', '258 Spruce Ave, Fairfield, ST 12352';
EXEC Customer.InsertSampleCustomer 'Christopher Lee', 'christopher.lee@email.com', '555-0109', '369 Willow St, Centerville, ST 12353', '369 Willow St, Centerville, ST 12353', '369 Willow St, Centerville, ST 12353';
EXEC Customer.InsertSampleCustomer 'Amanda White', 'amanda.white@email.com', '555-0110', '741 Poplar Rd, Midtown, ST 12354', '741 Poplar Rd, Midtown, ST 12354', '741 Poplar Rd, Midtown, ST 12354';

-- Get customer IDs for order creation
DECLARE @CustomerIDs TABLE (CustomerID UNIQUEIDENTIFIER, RowNum INT);
INSERT INTO @CustomerIDs (CustomerID, RowNum)
SELECT CustomerID, ROW_NUMBER() OVER (ORDER BY CreatedDate)
FROM Customer.Customer;

-- =============================================
-- Insert Customer Addresses
-- =============================================
PRINT 'Inserting customer addresses...';

DECLARE @Customer1 UNIQUEIDENTIFIER = (SELECT CustomerID FROM @CustomerIDs WHERE RowNum = 1);
DECLARE @Customer2 UNIQUEIDENTIFIER = (SELECT CustomerID FROM @CustomerIDs WHERE RowNum = 2);
DECLARE @Customer3 UNIQUEIDENTIFIER = (SELECT CustomerID FROM @CustomerIDs WHERE RowNum = 3);
DECLARE @Customer4 UNIQUEIDENTIFIER = (SELECT CustomerID FROM @CustomerIDs WHERE RowNum = 4);
DECLARE @Customer5 UNIQUEIDENTIFIER = (SELECT CustomerID FROM @CustomerIDs WHERE RowNum = 5);

-- Shipping Addresses
INSERT INTO Customer.ShippingAddress (CustomerID, AddressLine1, City, StateProvince, PostalCode, Country, IsDefault) VALUES
(@Customer1, '123 Main St', 'Anytown', 'ST', '12345', 'USA', 1),
(@Customer1, '456 Work Plaza', 'Anytown', 'ST', '12345', 'USA', 0),
(@Customer2, '456 Oak Ave', 'Springfield', 'ST', '12346', 'USA', 1),
(@Customer3, '789 Pine Rd', 'Riverside', 'ST', '12347', 'USA', 1),
(@Customer4, '321 Elm St', 'Lakewood', 'ST', '12348', 'USA', 1),
(@Customer5, '654 Maple Dr', 'Hillside', 'ST', '12349', 'USA', 1);

-- Billing Addresses
INSERT INTO Customer.BillingAddress (CustomerID, AddressLine1, City, StateProvince, PostalCode, Country, IsDefault) VALUES
(@Customer1, '123 Main St', 'Anytown', 'ST', '12345', 'USA', 1),
(@Customer2, '456 Oak Ave', 'Springfield', 'ST', '12346', 'USA', 1),
(@Customer3, '789 Pine Rd', 'Riverside', 'ST', '12347', 'USA', 1),
(@Customer4, '321 Elm St', 'Lakewood', 'ST', '12348', 'USA', 1),
(@Customer5, '654 Maple Dr', 'Hillside', 'ST', '12349', 'USA', 1);

-- =============================================
-- Insert Sample Orders using the ProcessOrder procedure
-- =============================================
PRINT 'Inserting sample orders...';

-- Disable order total calculation trigger temporarily
DISABLE TRIGGER tr_OrderDetail_UpdateOrderTotals ON Sales.OrderDetail;

DECLARE @OrderID UNIQUEIDENTIFIER;
DECLARE @TotalAmount DECIMAL(12,4);
DECLARE @ErrorMessage NVARCHAR(500);
DECLARE @ProductID UNIQUEIDENTIFIER;

-- Order 1: Electronics order
DECLARE @OrderItems1 NVARCHAR(MAX) = '[
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'IPH15PRO-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":999.99},
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'APPRO-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":249.99}
]';

EXEC Sales.ProcessOrder
    @CustomerID = @Customer1,
    @ShippingAddressID = 1,
    @BillingAddressID = 1,
    @ShippingMethod = 'Standard',
    @OrderItems = @OrderItems1,
    @TaxRate = 0.0875,
    @ShippingAmount = 9.99,
    @DiscountAmount = 0,
    @OrderID = @OrderID OUTPUT,
    @TotalAmount = @TotalAmount OUTPUT,
    @ErrorMessage = @ErrorMessage OUTPUT;

-- Update order status to simulate progression
UPDATE Sales.[Order] SET OrderStatus = 'Processing', PaymentStatus = 'Captured' WHERE OrderID = @OrderID;

-- Order 2: Clothing order
DECLARE @OrderItems2 NVARCHAR(MAX) = '[
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'MCT-001') AS NVARCHAR(50)) + '","Quantity":3,"UnitPrice":19.99},
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'MJ-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":79.99}
]';

EXEC Sales.ProcessOrder
    @CustomerID = @Customer2,
    @ShippingAddressID = 3,
    @BillingAddressID = 2,
    @ShippingMethod = 'Express',
    @OrderItems = @OrderItems2,
    @TaxRate = 0.0875,
    @ShippingAmount = 15.99,
    @DiscountAmount = 10.00,
    @OrderID = @OrderID OUTPUT,
    @TotalAmount = @TotalAmount OUTPUT,
    @ErrorMessage = @ErrorMessage OUTPUT;

UPDATE Sales.[Order] SET OrderStatus = 'Shipped', PaymentStatus = 'Captured', 
    ExpectedDeliveryDate = DATEADD(DAY, 2, GETUTCDATE()) WHERE OrderID = @OrderID;

-- Order 3: Home & Garden order
DECLARE @OrderItems3 NVARCHAR(MAX) = '[
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'KASM-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":379.99},
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'IPD-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":99.99}
]';

EXEC Sales.ProcessOrder
    @CustomerID = @Customer3,
    @ShippingAddressID = 4,
    @BillingAddressID = 3,
    @ShippingMethod = 'Standard',
    @OrderItems = @OrderItems3,
    @TaxRate = 0.0875,
    @ShippingAmount = 12.99,
    @DiscountAmount = 0,
    @OrderID = @OrderID OUTPUT,
    @TotalAmount = @TotalAmount OUTPUT,
    @ErrorMessage = @ErrorMessage OUTPUT;

UPDATE Sales.[Order] SET OrderStatus = 'Delivered', PaymentStatus = 'Captured',
    ExpectedDeliveryDate = DATEADD(DAY, 2, GETUTCDATE()),
    ActualDeliveryDate = DATEADD(DAY, 3, GETUTCDATE()) WHERE OrderID = @OrderID;

-- Order 4: Books order
DECLARE @OrderItems4 NVARCHAR(MAX) = '[
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'TGG-001') AS NVARCHAR(50)) + '","Quantity":2,"UnitPrice":12.99},
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'SAP-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":16.99},
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'AH-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":18.99}
]';

EXEC Sales.ProcessOrder
    @CustomerID = @Customer4,
    @ShippingAddressID = 5,
    @BillingAddressID = 4,
    @ShippingMethod = 'Economy',
    @OrderItems = @OrderItems4,
    @TaxRate = 0.0875,
    @ShippingAmount = 5.99,
    @DiscountAmount = 5.00,
    @OrderID = @OrderID OUTPUT,
    @TotalAmount = @TotalAmount OUTPUT,
    @ErrorMessage = @ErrorMessage OUTPUT;

UPDATE Sales.[Order] SET OrderStatus = 'Processing', PaymentStatus = 'Authorized' WHERE OrderID = @OrderID;

-- Order 5: Fitness equipment order
DECLARE @OrderItems5 NVARCHAR(MAX) = '[
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'YM-001') AS NVARCHAR(50)) + '","Quantity":2,"UnitPrice":29.99},
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'DS-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":149.99},
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'WB-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":24.99}
]';

EXEC Sales.ProcessOrder
    @CustomerID = @Customer5,
    @ShippingAddressID = 6,
    @BillingAddressID = 5,
    @ShippingMethod = 'Standard',
    @OrderItems = @OrderItems5,
    @TaxRate = 0.0875,
    @ShippingAmount = 8.99,
    @DiscountAmount = 15.00,
    @OrderID = @OrderID OUTPUT,
    @TotalAmount = @TotalAmount OUTPUT,
    @ErrorMessage = @ErrorMessage OUTPUT;

UPDATE Sales.[Order] SET OrderStatus = 'Shipped', PaymentStatus = 'Captured',
    ExpectedDeliveryDate = DATEADD(DAY, 3, GETUTCDATE()),
    TrackingNumber = 'TRK123456789' WHERE OrderID = @OrderID;

-- Create some historical orders (older dates)
DECLARE @HistoricalDate DATETIME2(3) = DATEADD(DAY, -45, GETUTCDATE());

-- Historical Order 1
DECLARE @HistOrderItems1 NVARCHAR(MAX) = '[
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'SGS24-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":899.99},
    {"ProductID":"' + CAST((SELECT TOP 1 ProductID FROM Inventory.Product WHERE ProductSKU = 'SXMN5-001') AS NVARCHAR(50)) + '","Quantity":1,"UnitPrice":399.99}
]';

EXEC Sales.ProcessOrder
    @CustomerID = @Customer1,
    @ShippingAddressID = 1,
    @BillingAddressID = 1,
    @ShippingMethod = 'Express',
    @OrderItems = @HistOrderItems1,
    @TaxRate = 0.0875,
    @ShippingAmount = 12.99,
    @DiscountAmount = 50.00,
    @OrderID = @OrderID OUTPUT,
    @TotalAmount = @TotalAmount OUTPUT,
    @ErrorMessage = @ErrorMessage OUTPUT;

-- Update to historical date and delivered status
UPDATE Sales.[Order] SET 
    OrderDate = @HistoricalDate,
    OrderStatus = 'Delivered', 
    PaymentStatus = 'Captured',
    ExpectedDeliveryDate = DATEADD(DAY, 5, @HistoricalDate),
    ActualDeliveryDate = DATEADD(DAY, 4, @HistoricalDate),
    CreatedDate = @HistoricalDate
WHERE OrderID = @OrderID;

-- Re-enable triggers
ENABLE TRIGGER tr_OrderDetail_UpdateOrderTotals ON Sales.OrderDetail;

-- =============================================
-- Insert Sample Returns
-- =============================================
PRINT 'Inserting sample returns...';

-- Create a return for one of the delivered orders
DECLARE @ReturnOrderID UNIQUEIDENTIFIER = (
    SELECT TOP 1 OrderID 
    FROM Sales.[Order] 
    WHERE OrderStatus = 'Delivered'
);

DECLARE @ReturnProductID UNIQUEIDENTIFIER = (
    SELECT TOP 1 ProductID 
    FROM Sales.OrderDetail 
    WHERE OrderID = @ReturnOrderID
);

DECLARE @OrderDate DATETIME2(3) =(
    SELECT TOP 1 OrderDate 
    FROM Sales.[Order] 
    WHERE OrderID = @ReturnOrderID
);
DECLARE @ReturnID UNIQUEIDENTIFIER;
EXEC Sales.ProcessReturn
    @OrderID = @ReturnOrderID,
	@OrderDate = @OrderDate,
    @ProductID = @ReturnProductID,
    @ReturnQuantity = 1,
    @ReturnReason = 'Customer changed mind',
    @RefundAmount = 99.99,
    @RestockProduct = 1,
    @ReturnID = @ReturnID OUTPUT,
    @ErrorMessage = @ErrorMessage OUTPUT;

-- =============================================
-- Insert Additional Inventory Transactions
-- =============================================
PRINT 'Inserting inventory adjustments...';

-- Add some inventory adjustments
-- First, get the ProductID
SELECT @ProductID = ProductID 
FROM Inventory.Product 
WHERE ProductSKU = 'IPH15PRO-001';

EXEC Inventory.UpdateProductInventory
    @ProductID = @ProductID,
    @AdjustmentType = 'Restock',
    @Quantity = 25,
    @Notes = 'Received new shipment from supplier',
    @ErrorMessage = @ErrorMessage OUTPUT;

-- First, get the ProductID
SELECT @ProductID = ProductID 
FROM Inventory.Product 
WHERE ProductSKU = 'MCT-001';

EXEC Inventory.UpdateProductInventory
    @ProductID = @ProductID,
    @AdjustmentType = 'Damage',
    @Quantity = -5,
    @Notes = 'Damaged items removed from inventory',
    @ErrorMessage = @ErrorMessage OUTPUT;

-- =============================================
-- Create some low stock scenarios for testing
-- =============================================
UPDATE Inventory.Product 
SET StockQuantity = 3, ReorderLevel = 5 
WHERE ProductSKU = 'MBP14-001';

UPDATE Inventory.Product 
SET StockQuantity = 0 
WHERE ProductSKU = 'DXPS13-001';

UPDATE Inventory.Product 
SET StockQuantity = 8, ReorderLevel = 15 
WHERE ProductSKU = 'SXMN5-001';

-- =============================================
-- Update some customer login dates for analytics
-- =============================================
UPDATE Customer.Customer 
SET LastLoginDate = DATEADD(DAY, -1, GETUTCDATE())
WHERE CustomerID IN (SELECT TOP 3 CustomerID FROM @CustomerIDs);

UPDATE Customer.Customer 
SET LastLoginDate = DATEADD(DAY, -7, GETUTCDATE())
WHERE CustomerID IN (SELECT CustomerID FROM @CustomerIDs WHERE RowNum BETWEEN 4 AND 6);

UPDATE Customer.Customer 
SET LastLoginDate = DATEADD(DAY, -30, GETUTCDATE())
WHERE CustomerID IN (SELECT CustomerID FROM @CustomerIDs WHERE RowNum BETWEEN 7 AND 8);

-- =============================================
-- Clean up temporary procedures
-- =============================================
DROP PROCEDURE Customer.InsertSampleCustomer;

-- Re-enable customer encryption trigger
ENABLE TRIGGER tr_Customer_EncryptData ON Customer.Customer;

-- =============================================
-- Generate Summary Report
-- =============================================
PRINT '================================================';
PRINT 'SAMPLE DATA INSERTION COMPLETED';
PRINT '================================================';

-- Categories summary
SELECT 'Categories' AS DataType, COUNT(*) AS RecordCount FROM Inventory.Category
UNION ALL
SELECT 'Products', COUNT(*) FROM Inventory.Product
UNION ALL
SELECT 'Customers', COUNT(*) FROM Customer.Customer
UNION ALL
SELECT 'Orders', COUNT(*) FROM Sales.[Order]
UNION ALL
SELECT 'Order Details', COUNT(*) FROM Sales.OrderDetail
UNION ALL
SELECT 'Inventory Transactions', COUNT(*) FROM Inventory.InventoryTransaction
UNION ALL
SELECT 'Product Returns', COUNT(*) FROM Sales.ProductReturn
UNION ALL
SELECT 'Shipping Addresses', COUNT(*) FROM Customer.ShippingAddress
UNION ALL
SELECT 'Billing Addresses', COUNT(*) FROM Customer.BillingAddress
UNION ALL
SELECT 'Audit Log Entries', COUNT(*) FROM Security.AuditLog
ORDER BY DataType;

PRINT '';
PRINT 'Sample orders by status:';
SELECT 
    OrderStatus,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalValue
FROM Sales.[Order]
GROUP BY OrderStatus
ORDER BY OrderCount DESC;

PRINT '';
PRINT 'Products by category:';
SELECT 
    c.CategoryName,
    COUNT(p.ProductID) AS ProductCount,
    AVG(p.Price) AS AvgPrice,
    SUM(p.StockQuantity) AS TotalStock
FROM Inventory.Category c
LEFT JOIN Inventory.Product p ON c.CategoryID = p.CategoryID
WHERE c.ParentCategoryID IS NOT NULL -- Only subcategories
GROUP BY c.CategoryName
ORDER BY ProductCount DESC;

PRINT '';
PRINT 'Low stock alerts:';
SELECT 
    p.ProductName,
    p.ProductSKU,
    p.StockQuantity,
    p.ReorderLevel,
    CASE 
        WHEN p.StockQuantity = 0 THEN 'OUT OF STOCK'
        WHEN p.StockQuantity <= p.ReorderLevel THEN 'LOW STOCK'
        ELSE 'OK'
    END AS Status
FROM Inventory.Product p
WHERE p.StockQuantity <= p.ReorderLevel
ORDER BY p.StockQuantity;

PRINT '';
PRINT 'Database is ready for testing and demonstration!';
PRINT 'You can now run queries against the views and test the stored procedures.';

GO