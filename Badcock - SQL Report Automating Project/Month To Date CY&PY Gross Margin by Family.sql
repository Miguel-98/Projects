	DECLARE @FromDate DATE = DATEADD(DD,1,EOMONTH(GETDATE(),-2))    
	DECLARE @ToDate DATE = EOMONTH(GETDATE(),-1)



	DROP TABLE IF EXISTS #Infor
	SELECT
		GL.ACCOUNT
		, SUM([NETFUNCTIONALAMOUNT]) AS 'TRANSAMT'
		, CONVERT (VARCHAR,[PERIODENDINGDATE],101) AS 'MONTHEND'
	INTO #Infor
	FROM [INFORCSFDW].[dbo].[INF_GENERALLEDGERTOTAL] GL
		LEFT JOIN INFORCSFDW.dbo.INF_GENERALLEDGERCHARTACCOUNT CA
			ON GL.ACCOUNT = CA.ACCOUNT 
		LEFT JOIN INFORCSFDW.dbo.INF_FINANCEDIMENSION3 S
			ON GL.FINANCEDIMENSION3 = S.FINANCEDIMENSION3 
	WHERE [PERIODENDINGDATE] BETWEEN @FromDate AND @ToDate
		AND GL.ACCOUNT BETWEEN '300000' AND '900000'
	--AND GL.FINANCEDIMENSION3 < '2000'
	GROUP BY  [PERIODENDINGDATE] ,GL.ACCOUNT
	HAVING SUM([NETFUNCTIONALAMOUNT]) <> 0
	ORDER BY [PERIODENDINGDATE],[ACCOUNT]



	DROP TABLE IF EXISTS #bta
	SELECT 
		@ToDate as 'MTD'
		,c.Family
		,bta.CategoryID
		,bta.OrderID
		,bta.OrderItemID
		,sum([SlsPrice]) as SlsPrice
		,sum([RtnPrice]) as RtnPrice
		,sum([NetDiscnt]) as NetDiscnt
		,sum([NetSales])as NetSales
		,sum([NetCost]) as NetCost
		,sum([GrossProfit])as GrossProfit
		,SUM( CASE WHEN v.CubicFeet = 0 
			THEN  0
			WHEN bta.GroupID LIKE 'DRCT%' THEN 0 
			ELSE (v.CubicFeet)*(bta.NetUnits) end ) as Volume
		,sum([NetUnits]) as NetUnits
		,sum(Case When [NetSales] < 0 then (i.Addon1Cost) * -1    Else i.Addon1Cost    End) as IntlFreight
		,sum(Case When [NetSales] < 0 then (i.Addon2Cost) * -1    Else i.Addon2Cost    End) as IntlDuty
		,sum(Case When [NetSales] < 0 then (i.LandedFreight) * -1 Else i.LandedFreight End) as DomesticFreight
		,ISNULL(sum(Case When [NetSales] < 0 then (D.DirectShipFreight) * -1 Else D.DirectShipFreight End),0) as DirectShipFreight
		,sum([NetCost]) - (sum(Case When [NetSales] < 0 then (i.Addon1Cost) * -1    Else i.Addon1Cost    End) + 
			sum(Case When [NetSales] < 0 then (i.Addon2Cost) * -1    Else i.Addon2Cost    End) +
			sum(Case When [NetSales] < 0 then (i.LandedFreight) * -1 Else i.LandedFreight End) +
			ISNULL(sum(Case When [NetSales] < 0 then (D.DirectShipFreight) * -1 Else D.DirectShipFreight End),0)) AS FactoryCost
	INTO #bta
	FROM (SELECT  
		  bta.CategoryID
         ,bta.OrderID
         ,bta.OrderItemID
		 ,bta.SourceID
		 ,bta.ProductID
		 ,bta.GroupID
		 ,sum(bta.NetUnits) as NetUnits
		 ,sum([SlsPrice]) as SlsPrice
         ,sum([RtnPrice]) as RtnPrice
         ,sum([NetDiscnt]) as NetDiscnt
         ,sum([NetSales])as NetSales
         ,sum([NetCost]) as NetCost
         ,sum([GrossProfit])as GrossProfit
		 FROM [BadcockDW].[storis].[BtaData]bta
	WHERE TransDate Between @FromDate And @ToDate 
			  AND WrittenFlag = '0' 
			  AND bta.KitStatus <> 'M' 
			  AND bta.StoreID <> '9093'
			  and bta.producttypeid = '1'
	GROUP BY bta.CategoryID
		,bta.OrderID
		,bta.OrderItemID
		,bta.SourceID
		,bta.ProductID
		,bta.GroupID) BTA
	INNER JOIN BadcockDW.storis.dw_Invoice inv     ON bta.OrderID=inv.OrderID
                                                   AND bta.SourceID=inv.SourceID
                                                   AND Inv.Repossession NOT IN (1,-1)                                
	LEFT JOIN BadcockDW.storis.Category c          ON bta.CategoryID = c.CategoryID
	LEFT JOIN BadcockDW.storis.Product V           ON BTA.ProductID=V.ProductID
	LEFT OUTER JOIN BadcockDW.storis.DW_InvoiceItem i ON bta.OrderID = i.OrderID 
											       AND bta.OrderItemID = i.ItemID
	LEFT JOIN (SELECT P.OrderID 
					, P.ItemID
					, SUM(P.Addon3Cost) as DirectShipFreight
				FROM BadcockDW.storis.InvoiceItem_ProductInfo p
				WHERE DateCreated Between @FromDate And @ToDate
				GROUP BY P.OrderID, P.ItemID) D
		ON BTA.OrderID = D.OrderID 
		AND BTA.OrderItemID = D.ItemID 
	group by Inv.Repossession
	  , bta.OrderID
	  , bta.OrderItemID
	  , bta.ProductID
	  , bta.CategoryID
	  , v.cubicfeet
	  , v.piececonvfactor
	  , c.Family

 

	DROP TABLE IF EXISTS #bta2
	SELECT MTD 
		, Family 
		, SUM(NetSales) AS NetSales
		, SUM(NetUnits) AS NetUnits
		, SUM(Volume) AS Volume
		, SUM(IntlFreight) AS IntlFreight
		, SUM(IntlDuty) AS IntlDuty
		, SUM(DomesticFreight) AS DomesticFreight
		, SUM(DirectShipFreight) AS DirectShipFreight
		, SUM(FactoryCost) AS FactoryCost
	INTO #BTA2
	FROM #bta 
	GROUP BY MTD, Family 




	DROP TABLE IF EXISTS #Discounts
	SELECT 
		MONTHEND ,
		SUM(transamt) AS Discounts
	INTO #Discounts
	FROM #Infor
	WHERE ACCOUNT BETWEEN '310000' AND '310152'
	GROUP BY MONTHEND


	DROP TABLE IF EXISTS #Freight 
	SELECT
		MONTHEND
		,-SUM(CASE WHEN ACCOUNT = '405100' THEN TRANSAMT END) AS IntlFreight
		,-SUM(CASE WHEN ACCOUNT = '405300' THEN TRANSAMT END) AS IntlDuty
		,-SUM(CASE WHEN ACCOUNT = '405000' THEN TRANSAMT END) AS DomesticFreight
		,-SUM(CASE WHEN ACCOUNT = '405400' THEN TRANSAMT END) AS DirectShipFreight
		,-SUM(CASE WHEN ACCOUNT = '405600' OR ACCOUNT = '406200' THEN TRANSAMT END) AS OtherFreight
		,-SUM(CASE WHEN ACCOUNT = '405200' OR ACCOUNT = '406500' THEN TRANSAMT END) AS Burden 
	INTO #Freight
	FROM #Infor
	GROUP BY MONTHEND




	DROP TABLE IF EXISTS #Freight2
	SELECT 
		 bta.MTD
		,bta.Family
		,ISNULL(CAST((SUM(bta.IntlFreight) + SUM(bta.IntlDuty) + SUM(bta.DomesticFreight) + SUM(bta.DirectShipFreight))+
		(-(SUM(bta.IntlFreight)     /MAX(TotIntlFreight)       * (MAX(TotIntlFreight)       + MAX(FF.IntlFreight)) +
		  SUM(bta.IntlDuty)         /MAX(TotIntlDuty)          * (MAX(TotIntlDuty)          + max(ff.IntlDuty))  + 
		  SUM(bta.DomesticFreight)  /MAX(TotDomesticFreight)   * (MAX(TotDomesticFreight)   + max(ff.DomesticFreight)) +
		  SUM(bta.DirectShipFreight)/MAX(TotDirectShipFreight) * (MAX(TotDirectShipFreight) + max(Ff.DirectShipFreight)))) +
		  (-SUM(f.OtherFreight) * (SUM(bta.Volume) /MAX(TotVolume))) AS NUMERIC),0) AS Freight
		, MAX(f.burden) AS Burden
		, MAX(d.discounts) AS Discounts
	INTO #Freight2
	FROM #bta2 bta
	LEFT JOIN (SELECT 
		 MONTHEND
		,SUM(IntlFreight) AS IntlFreight
		,SUM(IntlDuty) as IntlDuty
		,SUM(DomesticFreight) as DomesticFreight
		,SUM(DirectShipFreight) as DirectShipFreight
	FROM #Freight
	GROUP BY MONTHEND) FF
		ON BTA.MTD = FF.MONTHEND
	LEFT JOIN (SELECT 
		MTD     
      , CASE WHEN SUM(Volume) = 0 THEN 1 ELSE SUM(Volume) END AS TotVolume  
	  , CASE WHEN SUM([IntlFreight]) = 0 THEN 1 ELSE  SUM([IntlFreight]) END AS TotIntlFreight
	  , CASE WHEN SUM(IntlDuty) = 0 THEN 1 ELSE  SUM(IntlDuty) END AS TotIntlDuty
	  , CASE WHEN SUM(DomesticFreight) = 0 THEN 1 ELSE  SUM(DomesticFreight) END AS TotDomesticFreight
	  , CASE WHEN SUM(DirectShipFreight) = 0 THEN 1 ELSE  SUM(DirectShipFreight) END AS TotDirectShipFreight
	FROM #bta2 
	GROUP BY MTD) tot2
		ON tot2.MTD = BTA.MTD
	LEFT OUTER JOIN #Freight f
		ON f.MONTHEND = bta.MTD
	LEFT OUTER JOIN #Discounts d
		ON d.MONTHEND = bta.MTD
	GROUP BY bta.MTD
		,bta.Family



	DROP TABLE IF EXISTS #FinalCYGM
	SELECT 
		  BTA.MTD
		  , CASE WHEN fam.Family IN ('<Unknown>','BULKITEMS','FLOORING','HOMEOFFICE','OUTDR FURN','SPECLORDER','PROMO', 'HISTORY')
			THEN 'MISC' ELSE fam.Family END CYFamily
		  ,CAST(SUM(bta.netunits)/1000 AS NUMERIC) AS CYNetUnits
		  ,CAST(sum([NetSales])/1000 AS NUMERIC) - CAST(sum([NetSales])/MAX(tot.TotNetSales) * Sum(f2.Discounts) / 1000 AS NUMERIC) AS CYNetSales
		  ,FORMAT(sum([NetSales])/MAX(tot.TotNetSales), '0.00%') AS CYSalesMix
		  ,CAST(SUM(FactoryCost)/1000 AS NUMERIC) CYFactoryCost
		  ,CAST(SUM(f2.Freight)/1000 AS NUMERIC) AS CYFreight
		  ,-CAST((SUM(f2.Burden)/1000)  * (SUM(bta.Volume) / MAX(tot.TotVolume)) AS NUMERIC) AS CYBurden
	INTO #FinalCYGM 
	FROM (SELECT  
		FamilyID AS Family
	FROM BIDataWarehouse.edw.DimProduct
	WHERE Obsolete= 0
		AND ProductTypeID = '1'
	GROUP BY FamilyID) Fam

	LEFT JOIN #BTA2 bta
		ON BTA.Family = Fam.Family
	LEFT OUTER JOIN #Freight2 f2
		ON BTA.Family = f2.Family
	LEFT JOIN (SELECT 
		MTD
	  , SUM(NetSales) AS TotNetSales
      , SUM(Volume) AS TotVolume       
	FROM #bta
	GROUP BY MTD) tot
		ON BTA.MTD = TOT.MTD

	GROUP BY CASE WHEN fam.Family IN ('<Unknown>','BULKITEMS','FLOORING','HOMEOFFICE','OUTDR FURN','SPECLORDER','PROMO', 'HISTORY')
        THEN 'MISC' ELSE fam.Family END , BTA.MTD 
	HAVING CAST(sum([NetSales])/1000 AS NUMERIC) - CAST(sum([NetSales])/MAX(tot.TotNetSales) * Sum(f2.Discounts) / 1000 AS NUMERIC) IS NOT NULL
	ORDER BY CYFamily 



	DECLARE @PYFromDate DATE = DATEADD(DD,1,EOMONTH(GETDATE(),-15))    
	DECLARE @PYToDate DATE = EOMONTH(GETDATE(),-14)




	DROP TABLE IF EXISTS #PYInfor
	SELECT
		GL.ACCOUNT
		, SUM([NETFUNCTIONALAMOUNT]) AS 'TRANSAMT'
		, CONVERT (VARCHAR,[PERIODENDINGDATE],101) AS 'MONTHEND'
	INTO #PYInfor
	FROM [INFORCSFDW].[dbo].[INF_GENERALLEDGERTOTAL] GL
		LEFT JOIN INFORCSFDW.dbo.INF_GENERALLEDGERCHARTACCOUNT CA
			ON GL.ACCOUNT = CA.ACCOUNT 
		LEFT JOIN INFORCSFDW.dbo.INF_FINANCEDIMENSION3 S
			ON GL.FINANCEDIMENSION3 = S.FINANCEDIMENSION3 
	WHERE [PERIODENDINGDATE] BETWEEN @PYFromDate AND @PYToDate
		AND GL.ACCOUNT BETWEEN '300000' AND '900000'
	--AND GL.FINANCEDIMENSION3 < '2000'
	GROUP BY  [PERIODENDINGDATE] ,GL.ACCOUNT
	HAVING SUM([NETFUNCTIONALAMOUNT]) <> 0
	ORDER BY [PERIODENDINGDATE],[ACCOUNT]



	DROP TABLE IF EXISTS #PYbta
	SELECT 
		@PYToDate as 'MTD'
		,c.Family
		,bta.CategoryID
		,bta.OrderID
		,bta.OrderItemID
		,sum([SlsPrice]) as SlsPrice
		,sum([RtnPrice]) as RtnPrice
		,sum([NetDiscnt]) as NetDiscnt
		,sum([NetSales])as NetSales
		,sum([NetCost]) as NetCost
		,sum([GrossProfit])as GrossProfit
		,SUM( CASE WHEN v.CubicFeet = 0 
			THEN  0
			WHEN bta.GroupID LIKE 'DRCT%' THEN 0 
			ELSE (v.CubicFeet)*(bta.NetUnits) end ) as Volume
		,sum([NetUnits]) as NetUnits
		,sum(Case When [NetSales] < 0 then (i.Addon1Cost) * -1    Else i.Addon1Cost    End) as IntlFreight
		,sum(Case When [NetSales] < 0 then (i.Addon2Cost) * -1    Else i.Addon2Cost    End) as IntlDuty
		,sum(Case When [NetSales] < 0 then (i.LandedFreight) * -1 Else i.LandedFreight End) as DomesticFreight
		,ISNULL(sum(Case When [NetSales] < 0 then (D.DirectShipFreight) * -1 Else D.DirectShipFreight End),0) as DirectShipFreight
		,sum([NetCost]) - (sum(Case When [NetSales] < 0 then (i.Addon1Cost) * -1    Else i.Addon1Cost    End) + 
			sum(Case When [NetSales] < 0 then (i.Addon2Cost) * -1    Else i.Addon2Cost    End) +
			sum(Case When [NetSales] < 0 then (i.LandedFreight) * -1 Else i.LandedFreight End) +
			ISNULL(sum(Case When [NetSales] < 0 then (D.DirectShipFreight) * -1 Else D.DirectShipFreight End),0)) AS FactoryCost
	INTO #PYbta
	FROM (SELECT  
		  bta.CategoryID
         ,bta.OrderID
         ,bta.OrderItemID
		 ,bta.SourceID
		 ,bta.ProductID
		 ,bta.GroupID
		 ,sum(bta.NetUnits) as NetUnits
		 ,sum([SlsPrice]) as SlsPrice
         ,sum([RtnPrice]) as RtnPrice
         ,sum([NetDiscnt]) as NetDiscnt
         ,sum([NetSales])as NetSales
         ,sum([NetCost]) as NetCost
         ,sum([GrossProfit])as GrossProfit
	FROM [BadcockDW].[storis].[BtaData]bta
	WHERE TransDate Between @PYFromDate And @PYToDate 
		AND WrittenFlag = '0' 
		AND bta.KitStatus <> 'M' 
		AND bta.StoreID <> '9093'
		and bta.producttypeid = '1'
	GROUP BY bta.CategoryID
		,bta.OrderID
		,bta.OrderItemID
		,bta.SourceID
		,bta.ProductID
		,bta.GroupID) BTA
	INNER JOIN BadcockDW.storis.dw_Invoice inv        ON bta.OrderID=inv.OrderID
                                                      AND bta.SourceID=inv.SourceID
                                                      AND Inv.Repossession NOT IN (1,-1)                                
	LEFT JOIN BadcockDW.storis.Category c             ON bta.CategoryID = c.CategoryID
	LEFT JOIN BadcockDW.storis.Product V              ON BTA.ProductID=V.ProductID
	LEFT OUTER JOIN BadcockDW.storis.DW_InvoiceItem i ON bta.OrderID = i.OrderID 
											          AND bta.OrderItemID = i.ItemID
	LEFT JOIN (SELECT 
		P.OrderID 
		, P.ItemID
		, SUM(P.Addon3Cost) as DirectShipFreight
	FROM BadcockDW.storis.InvoiceItem_ProductInfo p
	WHERE DateCreated Between @PYFromDate And @PYToDate
	GROUP BY P.OrderID, P.ItemID) D
	ON BTA.OrderID = D.OrderID 
		AND BTA.OrderItemID = D.ItemID 
	GROUP BY Inv.Repossession
	  , bta.OrderID
	  , bta.OrderItemID
	  , bta.ProductID
	  , bta.CategoryID
	  , v.cubicfeet
	  , v.piececonvfactor
	  , c.Family

 

	DROP TABLE IF EXISTS #PYbta2
	SELECT MTD 
		, Family 
		, SUM(NetSales) AS NetSales
		, SUM(NetUnits) AS NetUnits
		, SUM(Volume) AS Volume
		, SUM(IntlFreight) AS IntlFreight
		, SUM(IntlDuty) AS IntlDuty
		, SUM(DomesticFreight) AS DomesticFreight
		, SUM(DirectShipFreight) AS DirectShipFreight
		, SUM(FactoryCost) AS FactoryCost
	INTO #PYBTA2
	FROM #PYbta 
	GROUP BY MTD, Family 




	DROP TABLE IF EXISTS #PYDiscounts
	SELECT 
		MONTHEND ,
		SUM(transamt) AS Discounts
	INTO #PYDiscounts
	FROM #PYInfor
	WHERE ACCOUNT BETWEEN '310000' AND '310152'
	GROUP BY MONTHEND


	DROP TABLE IF EXISTS #PYFreight 
	SELECT
		MONTHEND
		,-SUM(CASE WHEN ACCOUNT = '405100' THEN TRANSAMT END) AS IntlFreight
		,-SUM(CASE WHEN ACCOUNT = '405300' THEN TRANSAMT END) AS IntlDuty
		,-SUM(CASE WHEN ACCOUNT = '405000' THEN TRANSAMT END) AS DomesticFreight
		,-SUM(CASE WHEN ACCOUNT = '405400' THEN TRANSAMT END) AS DirectShipFreight
		,-SUM(CASE WHEN ACCOUNT = '405600' OR ACCOUNT = '406200' THEN TRANSAMT END) AS OtherFreight
		,-SUM(CASE WHEN ACCOUNT = '405200' OR ACCOUNT = '406500' THEN TRANSAMT END) AS Burden 
	INTO #PYFreight
	FROM #PYInfor
	GROUP BY MONTHEND




	DROP TABLE IF EXISTS #PYFreight2
	SELECT 
		bta.MTD
		,bta.Family
		,CAST((SUM(bta.IntlFreight) + SUM(bta.IntlDuty) + SUM(bta.DomesticFreight) + SUM(bta.DirectShipFreight))+
		(-(SUM(bta.IntlFreight)      /NULLIF(MAX(TotIntlFreight),0)       * (MAX(TotIntlFreight)       + MAX(FF.IntlFreight)) +
		  SUM(bta.IntlDuty)          /NULLIF(MAX(TotIntlDuty),0)          * (MAX(TotIntlDuty)          + max(ff.IntlDuty))  + 
		  SUM(bta.DomesticFreight)   /NULLIF(MAX(TotDomesticFreight),0)   * (MAX(TotDomesticFreight)   + max(ff.DomesticFreight)) +
		  SUM(bta.DirectShipFreight) /NULLIF(MAX(TotDirectShipFreight),0) * (MAX(TotDirectShipFreight) + max(Ff.DirectShipFreight)))) +
		  (-SUM(f.OtherFreight) * (SUM(bta.Volume) /NULLIF(MAX(TotVolume),0))) AS NUMERIC) AS Freight
		, MAX(f.burden) AS Burden
		, MAX(d.discounts) AS Discounts
	INTO #PYFreight2
	FROM #PYbta2 bta
	LEFT JOIN (SELECT 
		MONTHEND
		,SUM(IntlFreight) AS IntlFreight
		,SUM(IntlDuty)  as IntlDuty
		,SUM(DomesticFreight)  as DomesticFreight
		,SUM(DirectShipFreight)  as DirectShipFreight
	FROM #PYFreight
	GROUP BY MONTHEND) FF
	ON BTA.MTD = FF.MONTHEND
	LEFT JOIN (SELECT 
		MTD     
      , CASE WHEN SUM(Volume) = 0 THEN 1 ELSE SUM(Volume) END AS TotVolume  
	  , CASE WHEN SUM([IntlFreight]) = 0 THEN 1 ELSE  SUM([IntlFreight]) END AS TotIntlFreight
	  , CASE WHEN SUM(IntlDuty) = 0 THEN 1 ELSE  SUM(IntlDuty) END AS TotIntlDuty
	  , CASE WHEN SUM(DomesticFreight) = 0 THEN 1 ELSE  SUM(DomesticFreight) END AS TotDomesticFreight
	  , CASE WHEN SUM(DirectShipFreight) = 0 THEN 1 ELSE  SUM(DirectShipFreight) END AS TotDirectShipFreight
	FROM #PYbta2 
	GROUP BY MTD) tot2
		ON tot2.MTD = BTA.MTD
	LEFT OUTER JOIN #PYFreight f
		ON f.MONTHEND = bta.MTD
	LEFT OUTER JOIN #PYDiscounts d
		ON d.MONTHEND = bta.MTD
	GROUP BY bta.MTD
		,bta.Family



	DROP TABLE IF EXISTS #FinalPYGM
	SELECT 
		CASE WHEN fam.Family IN ('<Unknown>','BULKITEMS','FLOORING','HOMEOFFICE','OUTDR FURN','SPECLORDER','PROMO', 'HISTORY')
        THEN 'MISC' ELSE fam.Family END PYFamily
       ,CAST(SUM(bta.netunits)/1000 AS NUMERIC) AS PYNetUnits
	   ,CAST(sum([NetSales])/1000 AS NUMERIC) - CAST(sum([NetSales])/MAX(tot.TotNetSales) * Sum(f2.Discounts) / 1000 AS NUMERIC) AS PYNetSales
	   ,FORMAT(sum([NetSales])/MAX(tot.TotNetSales), '0.00%') AS PYSalesMix
	   ,CAST(SUM(FactoryCost)/1000 AS NUMERIC) PYFactoryCost
	   ,CAST(SUM(f2.Freight)/1000 AS NUMERIC) AS PYFreight
	   ,-CAST((SUM(f2.Burden)/1000)  * (SUM(bta.Volume) / MAX(tot.TotVolume)) AS NUMERIC) AS PYBurden
	INTO #FinalPYGM
	FROM (SELECT  
		FamilyID AS Family
	FROM BIDataWarehouse.edw.DimProduct
	WHERE Obsolete= 0
		AND ProductTypeID = '1'
	GROUP BY FamilyID) Fam
	LEFT JOIN #PYBTA2 bta
		ON BTA.Family = Fam.Family
	LEFT OUTER JOIN #PYFreight2 f2
		ON BTA.Family = f2.Family
	LEFT JOIN (SELECT
		MTD
	  , SUM(NetSales) AS TotNetSales
      , SUM(Volume) AS TotVolume       
	FROM #PYbta
	GROUP BY MTD) tot
		ON BTA.MTD = TOT.MTD

	GROUP BY CASE WHEN fam.Family IN ('<Unknown>','BULKITEMS','FLOORING','HOMEOFFICE','OUTDR FURN','SPECLORDER','PROMO', 'HISTORY')
			 THEN 'MISC' ELSE fam.Family END , BTA.MTD 
	HAVING CAST(sum([NetSales])/1000 AS NUMERIC) - CAST(sum([NetSales])/MAX(tot.TotNetSales) * Sum(f2.Discounts) / 1000 AS NUMERIC) IS NOT NULL
	ORDER BY PYFamily


	SELECT
	*
	, CYNetSales - CYFactoryCost - CYFreight - CYBurden AS CYGM
	, PYNetSales - PYFactoryCost - PYFreight - PYBurden AS PYGM
	FROM #FinalCYGM cy
	LEFT JOIN #FinalPYGM py
		ON cy.CYFamily = py.PYFamily
	ORDER BY  CYFamily