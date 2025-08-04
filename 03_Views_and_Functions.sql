-- =============================================
-- E-Commerce Views and Functions
-- Optimized data access and business logic
-- =============================================

USE ECommerceDB;
GO

-- =============================================
-- View: Customer Order History with Product Details
-- Provides comprehensive order information for customers
-- =============================================
CREATE OR ALTER VIEW Customer.vw_CustomerOrderHistory
AS
SELECT 
    o.OrderID,
    o.CustomerID,
    c.CustomerName,
    o.OrderDate,
    o.OrderStatus,
    o.PaymentStatus,
    o.TotalAmount,
    o.SubTotal,
    o.TaxAmount,
    o.ShippingAmount,
    o.DiscountAmount,
    o.TrackingNumber,
    o.ExpectedDeliveryDate,
    o.ActualDeliveryDate,
    
    -- Shipping Address
    sa.AddressLine1 + ISNULL(', ' + sa.AddressLine2, '') + ', ' + 
    sa.City + ', ' + sa.StateProvince + ' ' + sa.PostalCode AS ShippingAddress,
    
    -- Billing Address  
    ba.AddressLine1 + ISNULL(', ' + ba.AddressLine2, '') + ', ' + 
    ba.City + ', ' + ba.StateProvince + ' ' + ba.PostalCode AS BillingAddress,
    
    -- Product Details
    od.OrderDetailID,
    od.ProductID,
    p.ProductName,
    p.ProductSKU,
    cat.CategoryName,
    od.Quantity,
    od.UnitPrice,
    od.LineTotal,
    
    -- Order Metrics
    ROW_NUMBER() OVER (PARTITION BY o.CustomerID ORDER BY o.OrderDate DESC) AS OrderRank,
    COUNT(*) OVER (PARTITION BY o.CustomerID) AS CustomerTotalOrders,
    SUM(o.TotalAmount) OVER (PARTITION BY o.CustomerID) AS CustomerTotalSpent,
    
    -- Delivery Performance
    CASE 
        WHEN o.ActualDeliveryDate IS NOT NULL AND o.ExpectedDeliveryDate IS NOT NULL THEN
            DATEDIFF(DAY, o.ExpectedDeliveryDate, o.ActualDeliveryDate)
        ELSE NULL
    END AS DeliveryVarianceDays,
    
    CASE 
        WHEN o.ActualDeliveryDate IS NOT NULL THEN
            DATEDIFF(DAY, o.OrderDate, o.ActualDeliveryDate)
        ELSE NULL
    END AS TotalDeliveryDays

FROM Sales.[Order] o
INNER JOIN Customer.Customer c ON o.CustomerID = c.CustomerID
LEFT JOIN Customer.ShippingAddress sa ON o.ShippingAddressID = sa.ShippingAddressID
LEFT JOIN Customer.BillingAddress ba ON o.BillingAddressID = ba.BillingAddressID
INNER JOIN Sales.OrderDetail od ON o.OrderID = od.OrderID
INNER JOIN Inventory.Product p ON od.ProductID = p.ProductID
INNER JOIN Inventory.Category cat ON p.CategoryID = cat.CategoryID
WHERE c.IsActive = 1;
GO

-- =============================================
-- View: Product Performance Analytics
-- Comprehensive product sales and inventory metrics
-- =============================================
CREATE OR ALTER VIEW Inventory.vw_ProductPerformance
AS
WITH ProductSales AS (
    SELECT 
        p.ProductID,
        COUNT(DISTINCT od.OrderID) AS TotalOrders,
        SUM(od.Quantity) AS TotalQuantitySold,
        SUM(od.LineTotal) AS TotalRevenue,
        AVG(od.UnitPrice) AS AverageSellingPrice,
        MIN(o.OrderDate) AS FirstSaleDate,
        MAX(o.OrderDate) AS LastSaleDate,
        
        -- Last 30 days metrics
        SUM(CASE WHEN o.OrderDate >= DATEADD(DAY, -30, GETUTCDATE()) THEN od.Quantity ELSE 0 END) AS QuantitySoldLast30Days,
        SUM(CASE WHEN o.OrderDate >= DATEADD(DAY, -30, GETUTCDATE()) THEN od.LineTotal ELSE 0 END) AS RevenueLast30Days,
        
        -- Last 90 days metrics
        SUM(CASE WHEN o.OrderDate >= DATEADD(DAY, -90, GETUTCDATE()) THEN od.Quantity ELSE 0 END) AS QuantitySoldLast90Days,
        SUM(CASE WHEN o.OrderDate >= DATEADD(DAY, -90, GETUTCDATE()) THEN od.LineTotal ELSE 0 END) AS RevenueLast90Days
        
    FROM Inventory.Product p
    LEFT JOIN Sales.OrderDetail od ON p.ProductID = od.ProductID
    LEFT JOIN Sales.[Order] o ON od.OrderID = o.OrderID AND o.OrderStatus NOT IN ('Cancelled')
    GROUP BY p.ProductID
),
ProductReturns AS (
    SELECT 
        ProductID,
        COUNT(*) AS TotalReturns,
        SUM(ReturnQuantity) AS TotalReturnQuantity,
        SUM(RefundAmount) AS TotalRefundAmount
    FROM Sales.ProductReturn
    WHERE ReturnStatus = 'Processed'
    GROUP BY ProductID
)
SELECT 
    p.ProductID,
    p.ProductName,
    p.ProductSKU,
    c.CategoryName,
    p.Price AS CurrentPrice,
    p.StockQuantity,
    p.ReorderLevel,
    p.IsActive,
    
    -- Sales Metrics
    ISNULL(ps.TotalOrders, 0) AS TotalOrders,
    ISNULL(ps.TotalQuantitySold, 0) AS TotalQuantitySold,
    ISNULL(ps.TotalRevenue, 0) AS TotalRevenue,
    ISNULL(ps.AverageSellingPrice, p.Price) AS AverageSellingPrice,
    ps.FirstSaleDate,
    ps.LastSaleDate,
    
    -- Recent Performance
    ISNULL(ps.QuantitySoldLast30Days, 0) AS QuantitySoldLast30Days,
    ISNULL(ps.RevenueLast30Days, 0) AS RevenueLast30Days,
    ISNULL(ps.QuantitySoldLast90Days, 0) AS QuantitySoldLast90Days,
    ISNULL(ps.RevenueLast90Days, 0) AS RevenueLast90Days,
    
    -- Inventory Metrics
    CASE 
        WHEN p.StockQuantity = 0 THEN 'Out of Stock'
        WHEN p.StockQuantity <= p.ReorderLevel THEN 'Low Stock'
        WHEN p.StockQuantity > p.ReorderLevel * 3 THEN 'Overstock'
        ELSE 'In Stock'
    END AS StockStatus,
    
    -- Sales Velocity (units per day)
    CASE 
        WHEN ps.QuantitySoldLast30Days > 0 
        THEN CAST(ps.QuantitySoldLast30Days AS DECIMAL(10,2)) / 30.0
        ELSE 0
    END AS SalesVelocity30Days,
    
    -- Days of inventory remaining
    CASE 
        WHEN ps.QuantitySoldLast30Days > 0 AND p.StockQuantity > 0
        THEN CAST(p.StockQuantity AS DECIMAL(10,2)) / (CAST(ps.QuantitySoldLast30Days AS DECIMAL(10,2)) / 30.0)
        WHEN p.StockQuantity > 0 THEN 999.0
        ELSE 0.0
    END AS DaysOfInventoryRemaining,
    
    -- Return Metrics
    ISNULL(pr.TotalReturns, 0) AS TotalReturns,
    ISNULL(pr.TotalReturnQuantity, 0) AS TotalReturnQuantity,
    ISNULL(pr.TotalRefundAmount, 0) AS TotalRefundAmount,
    
    -- Return Rate
    CASE 
        WHEN ps.TotalQuantitySold > 0 
        THEN CAST(ISNULL(pr.TotalReturnQuantity, 0) AS DECIMAL(5,4)) / CAST(ps.TotalQuantitySold AS DECIMAL(10,2))
        ELSE 0
    END AS ReturnRate,
    
    -- Profitability Score (simplified)
    CASE 
        WHEN ps.TotalRevenue > 0 THEN
            (ps.TotalRevenue - ISNULL(pr.TotalRefundAmount, 0)) / ps.TotalRevenue
        ELSE 0
    END AS ProfitabilityScore

FROM Inventory.Product p
INNER JOIN Inventory.Category c ON p.CategoryID = c.CategoryID
LEFT JOIN ProductSales ps ON p.ProductID = ps.ProductID
LEFT JOIN ProductReturns pr ON p.ProductID = pr.ProductID;
GO

-- =============================================
-- View: Real-time Inventory Dashboard
-- Current inventory status with alerts
-- =============================================
CREATE OR ALTER VIEW Inventory.vw_InventoryDashboard
AS
SELECT 
    p.ProductID,
    p.ProductName,
    p.ProductSKU,
    c.CategoryName,
    p.StockQuantity,
    p.ReorderLevel,
    p.Price,
    
    -- Stock Status
    CASE 
        WHEN p.StockQuantity = 0 THEN 'OUT_OF_STOCK'
        WHEN p.StockQuantity <= p.ReorderLevel THEN 'LOW_STOCK'
        WHEN p.StockQuantity > p.ReorderLevel * 3 THEN 'OVERSTOCK'
        ELSE 'NORMAL'
    END AS StockStatus,
    
    -- Alert Level
    CASE 
        WHEN p.StockQuantity = 0 THEN 'CRITICAL'
        WHEN p.StockQuantity <= p.ReorderLevel THEN 'WARNING'
        WHEN p.StockQuantity > p.ReorderLevel * 3 THEN 'INFO'
        ELSE 'OK'
    END AS AlertLevel,
    
    -- Reorder Suggestion
    CASE 
        WHEN p.StockQuantity <= p.ReorderLevel 
        THEN p.ReorderLevel * 2 - p.StockQuantity
        ELSE 0
    END AS SuggestedReorderQuantity,
    
    -- Recent Activity
    it.LastTransaction,
    it.LastTransactionType,
    it.LastTransactionQuantity,
    
    -- Sales Performance
    pp.QuantitySoldLast30Days,
    pp.SalesVelocity30Days,
    pp.DaysOfInventoryRemaining

FROM Inventory.Product p
INNER JOIN Inventory.Category c ON p.CategoryID = c.CategoryID
LEFT JOIN (
    SELECT 
        ProductID,
        MAX(TransactionDate) AS LastTransaction,
        FIRST_VALUE(TransactionType) OVER (PARTITION BY ProductID ORDER BY TransactionDate DESC) AS LastTransactionType,
        FIRST_VALUE(Quantity) OVER (PARTITION BY ProductID ORDER BY TransactionDate DESC) AS LastTransactionQuantity
    FROM Inventory.InventoryTransaction
    GROUP BY ProductID, TransactionType, Quantity, TransactionDate
) it ON p.ProductID = it.ProductID
LEFT JOIN Inventory.vw_ProductPerformance pp ON p.ProductID = pp.ProductID
WHERE p.IsActive = 1;
GO

-- =============================================
-- Function: Calculate Shipping Cost
-- Dynamic shipping cost calculation based on weight and destination
-- =============================================
CREATE OR ALTER FUNCTION Sales.fn_CalculateShippingCost
(
    @OrderWeight DECIMAL(8,2), -- in pounds
    @DestinationZone NVARCHAR(10), -- 'LOCAL', 'REGIONAL', 'NATIONAL', 'INTERNATIONAL'
    @ShippingMethod NVARCHAR(50) -- 'Standard', 'Express', 'Overnight', 'Economy'
)
RETURNS DECIMAL(8,2)
AS
BEGIN
    DECLARE @ShippingCost DECIMAL(8,2) = 0;
    DECLARE @BaseRate DECIMAL(8,2) = 0;
    DECLARE @WeightMultiplier DECIMAL(8,2) = 0;
    DECLARE @ZoneMultiplier DECIMAL(8,2) = 1.0;
    DECLARE @MethodMultiplier DECIMAL(8,2) = 1.0;
    
    -- Set base rates by shipping method
    SET @BaseRate = CASE @ShippingMethod
        WHEN 'Economy' THEN 3.99
        WHEN 'Standard' THEN 5.99
        WHEN 'Express' THEN 12.99
        WHEN 'Overnight' THEN 24.99
        ELSE 5.99
    END;
    
    -- Set weight multiplier (cost per pound over 1 lb)
    SET @WeightMultiplier = CASE @ShippingMethod
        WHEN 'Economy' THEN 0.89
        WHEN 'Standard' THEN 1.25
        WHEN 'Express' THEN 2.50
        WHEN 'Overnight' THEN 4.99
        ELSE 1.25
    END;
    
    -- Set zone multiplier
    SET @ZoneMultiplier = CASE @DestinationZone
        WHEN 'LOCAL' THEN 0.8
        WHEN 'REGIONAL' THEN 1.0
        WHEN 'NATIONAL' THEN 1.3
        WHEN 'INTERNATIONAL' THEN 2.5
        ELSE 1.0
    END;
    
    -- Calculate shipping cost
    SET @ShippingCost = @BaseRate * @ZoneMultiplier;
    
    -- Add weight-based charges (for orders over 1 pound)
    IF @OrderWeight > 1.0
        SET @ShippingCost = @ShippingCost + ((@OrderWeight - 1.0) * @WeightMultiplier * @ZoneMultiplier);
    
    -- Apply minimum shipping cost
    IF @ShippingCost < 1.99
        SET @ShippingCost = 1.99;
    
    -- Apply maximum shipping cost for domestic orders
    IF @DestinationZone != 'INTERNATIONAL' AND @ShippingCost > 99.99
        SET @ShippingCost = 99.99;
    
    RETURN @ShippingCost;
END;
GO

-- =============================================
-- Function: Get Customer Tier
-- Determines customer tier based on purchase history
-- =============================================
CREATE OR ALTER FUNCTION Customer.fn_GetCustomerTier
(
    @CustomerID UNIQUEIDENTIFIER
)
RETURNS NVARCHAR(20)
AS
BEGIN
    DECLARE @CustomerTier NVARCHAR(20) = 'Bronze';
    DECLARE @TotalSpent DECIMAL(12,4) = 0;
    DECLARE @OrderCount INT = 0;
    DECLARE @DaysAsCustomer INT = 0;
    
    -- Get customer metrics
    SELECT 
        @TotalSpent = ISNULL(SUM(o.TotalAmount), 0),
        @OrderCount = COUNT(*),
        @DaysAsCustomer = DATEDIFF(DAY, MIN(o.OrderDate), GETUTCDATE())
    FROM Sales.[Order] o
    WHERE o.CustomerID = @CustomerID
    AND o.OrderStatus NOT IN ('Cancelled');
    
    -- Determine tier based on business rules
    IF @TotalSpent >= 10000.00 OR (@TotalSpent >= 5000.00 AND @OrderCount >= 50)
        SET @CustomerTier = 'Platinum';
    ELSE IF @TotalSpent >= 2500.00 OR (@TotalSpent >= 1000.00 AND @OrderCount >= 20)
        SET @CustomerTier = 'Gold';
    ELSE IF @TotalSpent >= 500.00 OR (@TotalSpent >= 250.00 AND @OrderCount >= 5)
        SET @CustomerTier = 'Silver';
    ELSE
        SET @CustomerTier = 'Bronze';
    
    RETURN @CustomerTier;
END;
GO

-- =============================================
-- Function: Calculate Product Discount
-- Dynamic discount calculation based on customer tier and product
-- =============================================
CREATE OR ALTER FUNCTION Sales.fn_CalculateProductDiscount
(
    @CustomerID UNIQUEIDENTIFIER,
    @ProductID UNIQUEIDENTIFIER,
    @Quantity INT,
    @UnitPrice DECIMAL(12,4)
)
RETURNS DECIMAL(12,4)
AS
BEGIN
    DECLARE @DiscountAmount DECIMAL(12,4) = 0;
    DECLARE @CustomerTier NVARCHAR(20);
    DECLARE @CategoryID INT;
    DECLARE @DiscountPercentage DECIMAL(5,4) = 0;
    
    -- Get customer tier
    SET @CustomerTier = Customer.fn_GetCustomerTier(@CustomerID);
    
    -- Get product category
    SELECT @CategoryID = CategoryID FROM Inventory.Product WHERE ProductID = @ProductID;
    
    -- Base tier discounts
    SET @DiscountPercentage = CASE @CustomerTier
        WHEN 'Platinum' THEN 0.15  -- 15%
        WHEN 'Gold' THEN 0.10      -- 10%
        WHEN 'Silver' THEN 0.05    -- 5%
        ELSE 0.00                  -- 0%
    END;
    
    -- Quantity discounts (additional)
    IF @Quantity >= 10
        SET @DiscountPercentage = @DiscountPercentage + 0.05;  -- Additional 5%
    ELSE IF @Quantity >= 5
        SET @DiscountPercentage = @DiscountPercentage + 0.02;  -- Additional 2%
    
    -- Category-specific promotions could be added here
    -- For now, using a simple category-based discount
    IF @CategoryID IN (1, 2, 3) -- Assuming categories 1,2,3 are promotional
        SET @DiscountPercentage = @DiscountPercentage + 0.03;  -- Additional 3%
    
    -- Cap maximum discount at 25%
    IF @DiscountPercentage > 0.25
        SET @DiscountPercentage = 0.25;
    
    -- Calculate discount amount
    SET @DiscountAmount = (@UnitPrice * @Quantity) * @DiscountPercentage;
    
    RETURN @DiscountAmount;
END;
GO

-- =============================================
-- Function: Get Order Delivery Estimate
-- Calculates estimated delivery date based on shipping method and destination
-- =============================================
CREATE OR ALTER FUNCTION Sales.fn_GetOrderDeliveryEstimate
(
    @OrderDate DATETIME2(3),
    @ShippingMethod NVARCHAR(50),
    @DestinationZone NVARCHAR(10)
)
RETURNS DATETIME2(3)
AS
BEGIN
    DECLARE @EstimatedDelivery DATETIME2(3);
    DECLARE @BusinessDays INT = 0;
    DECLARE @ZoneDays INT = 0;
    
    -- Base delivery days by shipping method
    SET @BusinessDays = CASE @ShippingMethod
        WHEN 'Overnight' THEN 1
        WHEN 'Express' THEN 2
        WHEN 'Standard' THEN 5
        WHEN 'Economy' THEN 7
        ELSE 5
    END;
    
    -- Additional days based on destination zone
    SET @ZoneDays = CASE @DestinationZone
        WHEN 'LOCAL' THEN 0
        WHEN 'REGIONAL' THEN 1
        WHEN 'NATIONAL' THEN 2
        WHEN 'INTERNATIONAL' THEN 5
        ELSE 1
    END;
    
    -- Calculate total business days
    SET @BusinessDays = @BusinessDays + @ZoneDays;
    
    -- Add business days to order date (excluding weekends)
    SET @EstimatedDelivery = @OrderDate;
    DECLARE @DaysAdded INT = 0;
    
    WHILE @DaysAdded < @BusinessDays
    BEGIN
        SET @EstimatedDelivery = DATEADD(DAY, 1, @EstimatedDelivery);
        
        -- Skip weekends
        IF DATEPART(WEEKDAY, @EstimatedDelivery) NOT IN (1, 7) -- Not Sunday or Saturday
            SET @DaysAdded = @DaysAdded + 1;
    END;
    
    RETURN @EstimatedDelivery;
END;
GO

-- =============================================
-- View: Customer Analytics Dashboard
-- Comprehensive customer insights and segmentation
-- =============================================
CREATE OR ALTER VIEW Customer.vw_CustomerAnalytics
AS
WITH CustomerMetrics AS (
    SELECT 
        c.CustomerID,
        c.CustomerName,
        c.CreatedDate,
        c.LastLoginDate,
        
        -- Order Metrics
        COUNT(o.OrderID) AS TotalOrders,
        ISNULL(SUM(o.TotalAmount), 0) AS TotalSpent,
        ISNULL(AVG(o.TotalAmount), 0) AS AverageOrderValue,
        MIN(o.OrderDate) AS FirstOrderDate,
        MAX(o.OrderDate) AS LastOrderDate,
        
        -- Recent Activity
        SUM(CASE WHEN o.OrderDate >= DATEADD(DAY, -30, GETUTCDATE()) THEN 1 ELSE 0 END) AS OrdersLast30Days,
        SUM(CASE WHEN o.OrderDate >= DATEADD(DAY, -90, GETUTCDATE()) THEN 1 ELSE 0 END) AS OrdersLast90Days,
        SUM(CASE WHEN o.OrderDate >= DATEADD(YEAR, -1, GETUTCDATE()) THEN 1 ELSE 0 END) AS OrdersLastYear,
        
        SUM(CASE WHEN o.OrderDate >= DATEADD(DAY, -30, GETUTCDATE()) THEN o.TotalAmount ELSE 0 END) AS SpentLast30Days,
        SUM(CASE WHEN o.OrderDate >= DATEADD(DAY, -90, GETUTCDATE()) THEN o.TotalAmount ELSE 0 END) AS SpentLast90Days,
        SUM(CASE WHEN o.OrderDate >= DATEADD(YEAR, -1, GETUTCDATE()) THEN o.TotalAmount ELSE 0 END) AS SpentLastYear
        
    FROM Customer.Customer c
    LEFT JOIN Sales.[Order] o ON c.CustomerID = o.CustomerID AND o.OrderStatus NOT IN ('Cancelled')
    WHERE c.IsActive = 1
    GROUP BY c.CustomerID, c.CustomerName, c.CreatedDate, c.LastLoginDate
),
CustomerReturns AS (
    SELECT 
        o.CustomerID,
        COUNT(*) AS TotalReturns,
        SUM(pr.RefundAmount) AS TotalRefundAmount
    FROM Sales.ProductReturn pr
    INNER JOIN Sales.[Order] o ON pr.OrderID = o.OrderID
    WHERE pr.ReturnStatus = 'Processed'
    GROUP BY o.CustomerID
)
SELECT 
    cm.CustomerID,
    cm.CustomerName,
    cm.CreatedDate,
    cm.LastLoginDate,
    
    -- Customer Tier
    Customer.fn_GetCustomerTier(cm.CustomerID) AS CustomerTier,
    
    -- Order History
    cm.TotalOrders,
    cm.TotalSpent,
    cm.AverageOrderValue,
    cm.FirstOrderDate,
    cm.LastOrderDate,
    
    -- Customer Lifecycle
    DATEDIFF(DAY, cm.CreatedDate, GETUTCDATE()) AS DaysAsCustomer,
    CASE 
        WHEN cm.LastOrderDate IS NULL THEN 'Never Ordered'
        WHEN cm.LastOrderDate >= DATEADD(DAY, -30, GETUTCDATE()) THEN 'Active'
        WHEN cm.LastOrderDate >= DATEADD(DAY, -90, GETUTCDATE()) THEN 'At Risk'
        ELSE 'Inactive'
    END AS CustomerStatus,
    
    -- Recency, Frequency, Monetary (RFM) Analysis
    CASE 
        WHEN cm.LastOrderDate IS NULL THEN 0
        ELSE DATEDIFF(DAY, cm.LastOrderDate, GETUTCDATE())
    END AS DaysSinceLastOrder,
    
    -- Purchase Frequency (orders per month)
    CASE 
        WHEN cm.FirstOrderDate IS NOT NULL AND DATEDIFF(MONTH, cm.FirstOrderDate, GETUTCDATE()) > 0
        THEN CAST(cm.TotalOrders AS DECIMAL(10,2)) / DATEDIFF(MONTH, cm.FirstOrderDate, GETUTCDATE())
        ELSE 0
    END AS OrdersPerMonth,
    
    -- Recent Activity
    cm.OrdersLast30Days,
    cm.OrdersLast90Days,
    cm.OrdersLastYear,
    cm.SpentLast30Days,
    cm.SpentLast90Days,
    cm.SpentLastYear,
    
    -- Return Behavior
    ISNULL(cr.TotalReturns, 0) AS TotalReturns,
    ISNULL(cr.TotalRefundAmount, 0) AS TotalRefundAmount,
    CASE 
        WHEN cm.TotalOrders > 0 
        THEN CAST(ISNULL(cr.TotalReturns, 0) AS DECIMAL(5,4)) / cm.TotalOrders
        ELSE 0
    END AS ReturnRate,
    
    -- Customer Value Score (simplified)
    CASE 
        WHEN cm.TotalSpent = 0 THEN 0
        ELSE (cm.TotalSpent * 0.6) + (cm.TotalOrders * 10 * 0.3) + 
             (CASE WHEN cm.OrdersLast90Days > 0 THEN 100 ELSE 0 END * 0.1)
    END AS CustomerValueScore

FROM CustomerMetrics cm
LEFT JOIN CustomerReturns cr ON cm.CustomerID = cr.CustomerID;
GO

-- =============================================
-- Function: Get Product Recommendations
-- Returns recommended products based on order history
-- =============================================
CREATE OR ALTER FUNCTION Sales.fn_GetProductRecommendations
(
    @CustomerID UNIQUEIDENTIFIER,
    @MaxRecommendations INT = 5
)
RETURNS TABLE
AS
RETURN
(
    WITH CustomerPurchases AS (
        SELECT DISTINCT od.ProductID, p.CategoryID
        FROM Sales.[Order] o
        INNER JOIN Sales.OrderDetail od ON o.OrderID = od.OrderID
        INNER JOIN Inventory.Product p ON od.ProductID = p.ProductID
        WHERE o.CustomerID = @CustomerID
        AND o.OrderStatus NOT IN ('Cancelled')
    ),
    CategoryPopularity AS (
        SELECT 
            p.CategoryID,
            COUNT(*) AS PopularityScore
        FROM CustomerPurchases cp
        INNER JOIN Inventory.Product p ON cp.CategoryID = p.CategoryID
        GROUP BY p.CategoryID
    ),
    RecommendedProducts AS (
        SELECT 
            p.ProductID,
            p.ProductName,
            p.ProductSKU,
            p.Price,
            c.CategoryName,
            pp.TotalQuantitySold,
            pp.AverageSellingPrice,
            cp.PopularityScore,
            ROW_NUMBER() OVER (ORDER BY cp.PopularityScore DESC, pp.TotalQuantitySold DESC) AS RecommendationRank
        FROM Inventory.Product p
        INNER JOIN Inventory.Category c ON p.CategoryID = c.CategoryID
        INNER JOIN CategoryPopularity cp ON p.CategoryID = cp.CategoryID
        LEFT JOIN Inventory.vw_ProductPerformance pp ON p.ProductID = pp.ProductID
        WHERE p.IsActive = 1
        AND p.StockQuantity > 0
        AND p.ProductID NOT IN (SELECT ProductID FROM CustomerPurchases)
    )
    SELECT TOP (@MaxRecommendations)
        ProductID,
        ProductName,
        ProductSKU,
        Price,
        CategoryName,
        TotalQuantitySold,
        AverageSellingPrice,
        PopularityScore,
        RecommendationRank
    FROM RecommendedProducts
    ORDER BY RecommendationRank
);
GO

-- =============================================
-- View: Sales Performance Dashboard
-- Executive dashboard for sales metrics and KPIs
-- =============================================
CREATE OR ALTER VIEW Sales.vw_SalesPerformanceDashboard
AS
WITH DateRanges AS (
    SELECT 
        CAST(GETUTCDATE() AS DATE) AS Today,
        DATEADD(DAY, -1, CAST(GETUTCDATE() AS DATE)) AS Yesterday,
        DATEADD(DAY, -7, GETUTCDATE()) AS Last7Days,
        DATEADD(DAY, -30, GETUTCDATE()) AS Last30Days,
        DATEADD(DAY, -90, GETUTCDATE()) AS Last90Days,
        DATEADD(YEAR, -1, GETUTCDATE()) AS LastYear,
        DATEADD(MONTH, DATEDIFF(MONTH, 0, GETUTCDATE()), 0) AS MonthStart,
        DATEADD(YEAR, DATEDIFF(YEAR, 0, GETUTCDATE()), 0) AS YearStart
),
SalesMetrics AS (
    SELECT 
        COUNT(CASE WHEN o.OrderDate >= dr.Today THEN 1 END) AS OrdersToday,
        COUNT(CASE WHEN o.OrderDate >= dr.Yesterday AND o.OrderDate < dr.Today THEN 1 END) AS OrdersYesterday,
        COUNT(CASE WHEN o.OrderDate >= dr.Last7Days THEN 1 END) AS OrdersLast7Days,
        COUNT(CASE WHEN o.OrderDate >= dr.Last30Days THEN 1 END) AS OrdersLast30Days,
        COUNT(CASE WHEN o.OrderDate >= dr.MonthStart THEN 1 END) AS OrdersThisMonth,
        COUNT(CASE WHEN o.OrderDate >= dr.YearStart THEN 1 END) AS OrdersThisYear,
        
        SUM(CASE WHEN o.OrderDate >= dr.Today THEN o.TotalAmount ELSE 0 END) AS RevenueToday,
        SUM(CASE WHEN o.OrderDate >= dr.Yesterday AND o.OrderDate < dr.Today THEN o.TotalAmount ELSE 0 END) AS RevenueYesterday,
        SUM(CASE WHEN o.OrderDate >= dr.Last7Days THEN o.TotalAmount ELSE 0 END) AS RevenueLast7Days,
        SUM(CASE WHEN o.OrderDate >= dr.Last30Days THEN o.TotalAmount ELSE 0 END) AS RevenueLast30Days,
        SUM(CASE WHEN o.OrderDate >= dr.MonthStart THEN o.TotalAmount ELSE 0 END) AS RevenueThisMonth,
        SUM(CASE WHEN o.OrderDate >= dr.YearStart THEN o.TotalAmount ELSE 0 END) AS RevenueThisYear,
        
        AVG(CASE WHEN o.OrderDate >= dr.Last30Days THEN o.TotalAmount END) AS AOVLast30Days,
        AVG(CASE WHEN o.OrderDate >= dr.MonthStart THEN o.TotalAmount END) AS AOVThisMonth,
        
        COUNT(DISTINCT CASE WHEN o.OrderDate >= dr.Last30Days THEN o.CustomerID END) AS UniqueCustomersLast30Days,
        COUNT(DISTINCT CASE WHEN o.OrderDate >= dr.MonthStart THEN o.CustomerID END) AS UniqueCustomersThisMonth
        
    FROM Sales.[Order] o
    CROSS JOIN DateRanges dr
    WHERE o.OrderStatus NOT IN ('Cancelled')
)
SELECT 
    -- Today's Performance
    sm.OrdersToday,
    sm.RevenueToday,
    
    -- Yesterday's Performance  
    sm.OrdersYesterday,
    sm.RevenueYesterday,
    
    -- Growth Rates
    CASE 
        WHEN sm.OrdersYesterday > 0 
        THEN ((CAST(sm.OrdersToday AS DECIMAL(10,2)) - sm.OrdersYesterday) / sm.OrdersYesterday) * 100
        ELSE 0
    END AS OrderGrowthRate,
    
    CASE 
        WHEN sm.RevenueYesterday > 0 
        THEN ((sm.RevenueToday - sm.RevenueYesterday) / sm.RevenueYesterday) * 100
        ELSE 0
    END AS RevenueGrowthRate,
    
    -- Period Performance
    sm.OrdersLast7Days,
    sm.RevenueLast7Days,
    sm.OrdersLast30Days,
    sm.RevenueLast30Days,
    sm.OrdersThisMonth,
    sm.RevenueThisMonth,
    sm.OrdersThisYear,
    sm.RevenueThisYear,
    
    -- Key Metrics
    sm.AOVLast30Days,
    sm.AOVThisMonth,
    sm.UniqueCustomersLast30Days,
    sm.UniqueCustomersThisMonth,
    
    -- Customer Metrics
    CASE 
        WHEN sm.UniqueCustomersLast30Days > 0 
        THEN sm.RevenueLast30Days / sm.UniqueCustomersLast30Days
        ELSE 0
    END AS RevenuePerCustomerLast30Days,
    
    CASE 
        WHEN sm.UniqueCustomersLast30Days > 0 
        THEN CAST(sm.OrdersLast30Days AS DECIMAL(10,2)) / sm.UniqueCustomersLast30Days
        ELSE 0
    END AS OrdersPerCustomerLast30Days

FROM SalesMetrics sm;
GO

PRINT 'Views and functions created successfully.';
GO