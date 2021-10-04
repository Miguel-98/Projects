	DECLARE @End DATE = @EndOfMonth



	DROP TABLE IF EXISTS #temp
	SELECT  
		EOMONTH(InvoiceDate) AS InvoiceDate
		, ISNULL(PG.Group_Name, 'Cash') AS GroupName 
		, ISNULL(FinancePaymentTypeID, 'Cash') AS FinancePaymentTypeID 
		, CASE WHEN InvoiceDate BETWEEN DATEADD(dd, 1, EOMONTH(@End, -1)) AND @End THEN SUM(TotInvcAmt) ELSE NULL END AS CurrentInvoicedAMT
		, CASE WHEN InvoiceDate BETWEEN DATEADD(dd, 1, EOMONTH(@End, -13)) AND EOMONTH(@End, -12) THEN SUM(TotInvcAmt) ELSE NULL END AS PriorInvoicedAMT
		, CASE WHEN InvoiceDate BETWEEN DATEADD(dd, 1, EOMONTH(@End, -1)) AND @End THEN COUNT(DISTINCT OrderID) ELSE NULL END AS CurrentInvoiceCount
		, CASE WHEN InvoiceDate BETWEEN DATEADD(dd, 1, EOMONTH(@End, -13)) AND EOMONTH(@End, -12) THEN COUNT(DISTINCT OrderID) ELSE NULL END AS PriorInvoiceCount
		, Sum(TotInvcAmt) AS TotalInvoiceAmount
	INTO #temp
	FROM BadcockDW.storis.DW_Invoice I
		LEFT JOIN STOREnetDW.dbo.ARPlanInformation PL
			ON I.FinancePaymentTypeID = PL.PlanID 
		LEFT JOIN STOREnetDW.dbo.ARPlanGroups PG
			ON PL.GroupID = PG.GroupID  
	WHERE 
		(InvoiceDate BETWEEN DATEADD(dd, 1, EOMONTH(@End, -13)) AND @End)
		AND TransCodeID = '0'
	GROUP BY InvoiceDate
		, FinancePaymentTypeID 
		, PG.Group_Name 



	DROP TABLE IF EXISTS #TempFinal
	SELECT * 
		,CASE WHEN groupname = 'EPNI' then 3
			WHEN groupname = 'Cash' THEN 1
			WHEN groupname = 'Revolving' THEN 2
			ELSE 99 END AS SortOrder
	INTO #TempFinal
	FROM(
	SELECT  
		'CashTable' AS Type
		, REPLACE(REPLACE(REPLACE(GroupName, 'Third Party', 'Cash'), 'ON-Account', 'Revolving'), 'Same As Cash', 'EPNI') GroupName
		, SUM(ISNULL( CurrentInvoicedAMT, 0)) CurrentInvoicedAMT
		, SUM(ISNULL( PriorInvoicedAMT, 0)) PriorInvoicedAMT
		, SUM(ISNULL(CurrentInvoiceCount, 0)) CurrentInvoiceCount
		, SUM(ISNULL( PriorInvoiceCount, 0)) PriorInvoiceCount
	FROM #temp
	GROUP BY REPLACE(REPLACE(GroupName, 'Third Party', 'Cash'), 'ON-Account', 'Revolving')

	UNION ALL

	SELECT
		'RevolvingTable' 
		, REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(FinancePaymentTypeID, 'REVC1', 'Other'), 'RC1AL', 'Other'), 'CRPEM', 'Other'), 'BK00', 'Other'), 'RC1FL', 'Other'), 'HPP' , 'Other') GroupName 
		, SUM(ISNULL( CurrentInvoicedAMT, 0)) CurrentInvoicedAMT
		, SUM(ISNULL( PriorInvoicedAMT, 0)) PriorInvoicedAMT
		, SUM(ISNULL(CurrentInvoiceCount, 0)) CurrentInvoiceCount
		, SUM(ISNULL( PriorInvoiceCount, 0)) PriorInvoiceCount
	FROM #temp
	WHERE GroupName = 'ON-Account'
-- ORFinancePaymentTypeID like ('NCR%')
-- OR FinancePaymentTypeID = 'RASPP'
	GROUP BY 
		REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(FinancePaymentTypeID, 'REVC1', 'Other'), 'RC1AL', 'Other'), 'CRPEM', 'Other'), 'BK00', 'Other'), 'RC1FL', 'Other'), 'HPP' , 'Other')

	UNION ALL

	SELECT
		'ENI' 
		, FinancePaymentTypeID
		, SUM(ISNULL( CurrentInvoicedAMT, 0)) CurrentInvoicedAMT
		, SUM(ISNULL( PriorInvoicedAMT, 0)) PriorInvoicedAMT
		, SUM(ISNULL(CurrentInvoiceCount, 0)) CurrentInvoiceCount
		, SUM(ISNULL( PriorInvoiceCount, 0)) PriorInvoiceCount 
	FROM #temp
	WHERE FinancePaymentTypeID LIKE ('ENI%')
	GROUP BY FinancePaymentTypeID) final



	SELECT tf.*
		, TotCurrentInvoicedAmt
		, TotCurrentInvoicedCount
		, PriorTotInvoicedAmt
		, PriorTotInvoicedCount
		, TotRevolvingInvoiceAmt
		, tot2.TotPriorRevolvingInvoiceAmt
		, tot3.TotEPNIInvoiceAmt
		, tot3.TotPriorEPNIInvoiceAmt
	FROM #TempFinal tf
	CROSS APPLY
	(SELECT 
		SUM(CurrentInvoicedAMT) TotCurrentInvoicedAmt
		, SUM(CurrentInvoiceCount) TotCurrentInvoicedCount
		, SUM(PriorInvoiceCount) PriorTotInvoicedCount
		, SUM(PriorInvoicedAMT) PriorTotInvoicedAmt
	FROM #tempFinal 
	WHERE Type = 'CashTable') tot
	CROSS APPLY
	(SELECT 
		SUM(CurrentInvoicedAMT) TotRevolvingInvoiceAmt
		, SUM(PriorInvoicedAMT) TotPriorRevolvingInvoiceAmt
	FROM #tempFinal Where GroupName = 'Revolving') tot2
	CROSS APPLY
	(SELECT 
		SUM(CurrentInvoicedAMT) TotEPNIInvoiceAmt
		,SUM(PriorInvoicedAmt) TotPriorEPNIInvoiceAmt
	FROM #TempFinal  
	WHERE GroupName = 'EPNI') tot3