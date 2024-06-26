﻿
DECLARE @BaseDay as Date =	'2011-11-18' , @m  as INT  =  1
IF DAY(@BaseDay) = 1  --If it is the 1st day of the month, calculate the previous month
		   BEGIN
		   SET @m = @m + 1
		   END
DECLARE @MTDIndicator	AS DATE = Dateadd(Day,1,EOMonth(dateadd(MONTH,-@m,@BaseDay)))

DROP TABLE IF EXISTS #Temporary

;WITH MTD_Calculation AS
(
SELECT
   CAST(CreatedAt_DateTime AS DATE) CreatedAt_Date
  ,CASE WHEN GROUPING(ProductName) = 1 AND GROUPING(Country) = 1 THEN 'Total' 
		WHEN GROUPING(ProductName) = 1 THEN 'SubTotal' 
		ELSE ProductName END  AS ProductName
  ,CASE WHEN GROUPING(ProductName) = 1 AND GROUPING(Country) = 1 THEN 'Total' 
		WHEN GROUPING(Country) = 1 THEN 'SubTotal' 
		ELSE Country END  AS CountryName
  ,SUM(UnitPrice*Quantity) TransactionVolume
  ,SUM(Quantity) TransactionCount 
  ,UserId 
FROM Transactions (NOLOCK) 
WHERE   CreatedAt_DateTime >= @MTDIndicator
	AND CreatedAt_DateTime <  @BaseDay
GROUP BY CAST(CreatedAt_DateTime AS DATE), CUBE(ProductName ,Country) ,UserId 
)

SELECT CreatedAt_Date as  [Date] ,ProductName ,CountryName 
       ,COUNT(DISTINCT UserId) As TotalUniqueUser
	   ,SUM(TransactionCount)			As TotalTxCount
	   ,SUM(TransactionVolume)				As TotalTxVolume
       ,SUM(COUNT(CASE WHEN seqnum = 1 THEN UserId END )) OVER (Partition by YEAR(CreatedAt_Date),MONTH(CreatedAt_Date),ProductName ,CountryName ORDER BY CreatedAt_Date) As TotalUniqueUserMTD
	   ,SUM(SUM(TransactionCount)) OVER (Partition by YEAR(CreatedAt_Date),MONTH(CreatedAt_Date),ProductName ,CountryName ORDER BY CreatedAt_Date)  As TotalTxCountMTD
	   ,SUM(SUM(TransactionVolume)) OVER (Partition by YEAR(CreatedAt_Date),MONTH(CreatedAt_Date),ProductName ,CountryName ORDER BY CreatedAt_Date)  As TotalTxVolumeMTD
	--Window Functions for MTD calculation
INTO #Temporary
FROM (SELECT t.*,
             ROW_NUMBER() OVER (PARTITION BY YEAR(CreatedAt_Date),MONTH(CreatedAt_Date),UserId,ProductName ,CountryName  ORDER BY CreatedAt_Date) as seqnum
			 --assign a sequence number to find monthly unique users
	  FROM MTD_Calculation t
     ) t
GROUP BY CreatedAt_Date,ProductName ,CountryName


INSERT INTO #Temporary
--Since there will be days in which no transactions are completed for each product and each country, we add empty days manually.
SELECT CreateDate, ProductName, CountryName, 0, 0, 0, NULL, NULL, NULL
FROM (
	SELECT CreateDate, ProductName, CountryName
	FROM (select distinct ProductName,CountryName from #Temporary
		) x
	CROSS JOIN Calendar c
	WHERE c.CreateDate >=  @MTDIndicator 
		AND c.CreateDate < @BaseDay

	EXCEPT
	SELECT DISTINCT [Date], ProductName, CountryName
	FROM #Temporary (NOLOCK)
	) x
; 
 
--assign zero to null values for the first day of the month
UPDATE a 
set TotalUniqueUserMTD = 0
from #Temporary (nolock) a
where  (datepart(day,[Date]) = 1) and TotalUniqueUserMTD  Is Null AND a.[Date] >= @MTDIndicator AND a.[Date] < @BaseDay
; 
UPDATE a 
set TotalTxCountMTD = 0
from #Temporary (nolock) a
where  (datepart(day,[Date]) = 1) and TotalTxCountMTD  Is Null AND a.[Date] >= @MTDIndicator AND a.[Date] < @BaseDay
; 
UPDATE a 
set TotalTxVolumeMTD = 0
from #Temporary (nolock) a
where  (datepart(day,[Date]) = 1) and TotalTxVolumeMTD  Is Null AND a.[Date] >= @MTDIndicator AND a.[Date] < @BaseDay
; 


while --find null values ​​for the other days and fill them one by one with the value of the previous day
	(select count(1) from  #Temporary (nolock) 
	 where  [Date] >= @MTDIndicator AND [Date] < @BaseDay 
		AND (TotalUniqueUserMTD is null or TotalTxCountMTD is null or TotalTxVolumeMTD is null)
	) > 0 
BEGIN 
UPDATE a2
set a2.TotalUniqueUserMTD = a.TotalUniqueUserMTD
from #Temporary (nolock) a2   
Join #Temporary (nolock) a on a2.[Date] = dateadd(day,1,a.[Date])  
where   a2.TotalUniqueUserMTD Is Null AND a2.[Date] >= @MTDIndicator AND a2.[Date] < @BaseDay   
		and a.TotalUniqueUserMTD  is not null AND a.CountryName = a2.CountryName AND a.ProductName = a2.ProductName
UPDATE a2
set a2.TotalTxCountMTD = a.TotalTxCountMTD
from #Temporary (nolock) a2   
Join #Temporary (nolock) a on a2.[Date] = dateadd(day,1,a.[Date])  
where   a2.TotalTxCountMTD Is Null AND a2.[Date] >= @MTDIndicator AND a2.[Date] < @BaseDay   
		and a.TotalTxCountMTD  is not null AND a.CountryName = a2.CountryName AND a.ProductName = a2.ProductName
UPDATE a2
set a2.TotalTxVolumeMTD = a.TotalTxVolumeMTD
from #Temporary (nolock) a2   
Join #Temporary (nolock) a on a2.[Date] = dateadd(day,1,a.[Date])  
where   a2.TotalTxVolumeMTD Is Null AND a2.[Date] >= @MTDIndicator AND a2.[Date] < @BaseDay   
		and a.TotalTxVolumeMTD  is not null AND a.CountryName = a2.CountryName AND a.ProductName = a2.ProductName
End
  
SELECT * FROM #Temporary  ORDER BY 2,3,1
--Now, the temp table we created is ready for use. You can either populate a table with this query or use it daily through a stored procedure. It can be adjusted according to the need.
 