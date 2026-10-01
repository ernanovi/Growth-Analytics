
-- 1. MARKETING PERFORMANCE
CREATE OR REPLACE VIEW
`ritzhelper.ritzhelper_dwh.v_master_marketing_performance` AS
WITH
-- PAID CUSTOMERS
paid_customers AS (

  SELECT
    p.Payment_ID,
    p.Customer_ID,
    p.Lead_ID,
    p.Paid_Date,
    p.Service_Type,
    p.Frequency,
    p.Recurring_Customer_,
    p.First_30D_Booked_Hours,
    p.Revenue_Ex_GST,
    c.Customer_History_Flag

  FROM `ritzhelper.ritzhelper_dwh.pay_book` p

  LEFT JOIN `ritzhelper.ritzhelper_dwh.cust_history` c
    ON p.Customer_ID = c.Customer_ID

  WHERE p.Payment_Status = 'Paid'
),

-- LEADS + FIRST TOUCH CUSTOMER
--
-- Satu Customer ID hanya dianggap 1 potential customer.
-- Customer diberikan ke lead pertama berdasarkan Created_Date.

leads_with_first_touch AS (

  SELECT

    Lead_ID,
    Created_Date,
    Customer_ID,
    Source,
    Campaign,
    Ad_Set___Ad_Group,
    Ad___Creative,

    ROW_NUMBER() OVER (
      PARTITION BY Customer_ID
      ORDER BY
        Created_Date ASC,
        Lead_ID ASC
    ) AS Customer_First_Touch_Rank

  FROM `ritzhelper.ritzhelper_dwh.leads`
),


-- AD SPEND

ad_aggregated AS (

  SELECT

    Platform,
    Campaign,
    Ad_Set___Ad_Group AS Ad_Set,
    Ad___Creative AS Ad_Creative,

    SUM(Spend) AS Total_Spend,

    SUM(Platform_Reported_Leads)
      AS Platform_Reported_Leads

  FROM `ritzhelper.ritzhelper_dwh.ad_spend`

  GROUP BY
    Platform,
    Campaign,
    Ad_Set,
    Ad_Creative
),



-- CRM LEADS
--
-- CRM Leads = DISTINCT Lead ID
-- Unique Potential Customer = Customer ID hanya pada
-- first-touch lead


lead_aggregated AS (

  SELECT

    Source AS Platform,
    Campaign,
    Ad_Set___Ad_Group AS Ad_Set,
    Ad___Creative AS Ad_Creative,

    -- Semua lead tetap dihitung
    COUNT(DISTINCT Lead_ID)
      AS CRM_Leads,

    -- Customer hanya dihitung satu kali secara global
    COUNT(
      DISTINCT CASE
        WHEN Customer_First_Touch_Rank = 1
        THEN Customer_ID
      END
    ) AS Unique_Potential_Customers

  FROM leads_with_first_touch

  GROUP BY
    Source,
    Campaign,
    Ad_Set___Ad_Group,
    Ad___Creative
),



-- PAID CUSTOMER
--
-- TIDAK menggunakan first-touch.
-- Payment tetap mengikuti Lead ID yang menghasilkan payment.

paid_aggregated AS (

  SELECT

    l.Source AS Platform,
    l.Campaign,
    l.Ad_Set___Ad_Group AS Ad_Set,
    l.Ad___Creative AS Ad_Creative,

    -- New Paying Customers
    COUNT(DISTINCT pc.Customer_ID)
      AS New_Paying_Customers,

    -- New Recurring Customers
    COUNT(
      DISTINCT CASE
        WHEN pc.Recurring_Customer_ = TRUE
        THEN pc.Customer_ID
      END
    ) AS New_Recurring_Customers,

    -- Revenue customer baru
    SUM(pc.Revenue_Ex_GST)
      AS Total_Revenue_Ex_GST

  FROM `ritzhelper.ritzhelper_dwh.leads` l

  INNER JOIN paid_customers pc
    ON l.Lead_ID = pc.Lead_ID

  WHERE pc.Customer_History_Flag =
        'New at start of Aug'

  GROUP BY
    l.Source,
    l.Campaign,
    l.Ad_Set___Ad_Group,
    l.Ad___Creative
),


-- COMBINE

base AS (

  SELECT

    COALESCE(
      a.Platform,
      l.Platform,
      p.Platform
    ) AS Platform,

    COALESCE(
      a.Campaign,
      l.Campaign,
      p.Campaign
    ) AS Campaign,

    COALESCE(
      a.Ad_Set,
      l.Ad_Set,
      p.Ad_Set
    ) AS Ad_Set,

    COALESCE(
      a.Ad_Creative,
      l.Ad_Creative,
      p.Ad_Creative
    ) AS Ad_Creative,

    COALESCE(
      a.Total_Spend,
      0
    ) AS Total_Spend,

    COALESCE(
      a.Platform_Reported_Leads,
      0
    ) AS Platform_Reported_Leads,

    COALESCE(
      l.CRM_Leads,
      0
    ) AS CRM_Leads,

    COALESCE(
      l.Unique_Potential_Customers,
      0
    ) AS Unique_Potential_Customers,

    COALESCE(
      p.New_Paying_Customers,
      0
    ) AS New_Paying_Customers,

    COALESCE(
      p.New_Recurring_Customers,
      0
    ) AS New_Recurring_Customers,

    COALESCE(
      p.Total_Revenue_Ex_GST,
      0
    ) AS Total_Revenue_Ex_GST

  FROM ad_aggregated a

  FULL OUTER JOIN lead_aggregated l

    USING (
      Platform,
      Campaign,
      Ad_Set,
      Ad_Creative
    )

  FULL OUTER JOIN paid_aggregated p

    USING (
      Platform,
      Campaign,
      Ad_Set,
      Ad_Creative
    )
)



-- FINAL MARKETING VIEW


SELECT

  Platform,
  Campaign,
  Ad_Set,
  Ad_Creative,

  CRM_Leads,

  New_Paying_Customers,

  New_Recurring_Customers,

  Platform_Reported_Leads,

  Total_Revenue_Ex_GST,

  Total_Spend,

  Unique_Potential_Customers,

  -- CPA
  ROUND(
    SAFE_DIVIDE(
      Total_Spend,
      New_Paying_Customers
    ),
    2
  ) AS CPA,

  -- Recurring CPA
  ROUND(
    SAFE_DIVIDE(
      Total_Spend,
      New_Recurring_Customers
    ),
    2
  ) AS Recurring_CPA,

  -- ROAS
  ROUND(
    SAFE_DIVIDE(
      Total_Revenue_Ex_GST,
      Total_Spend
    ),
    2
  ) AS ROAS

FROM base;



-- 2. HELPER CAPACITY

CREATE OR REPLACE VIEW
`ritzhelper.ritzhelper_dwh.v_master_helper_capacity` AS

WITH cleaned_capacity AS (

  SELECT

    Date,
    Helper_ID,
    Shift,

    Available_Hours,

    CASE
      WHEN Booked_Hours IN (5, 15, 25, 35)
        THEN Booked_Hours / 10
      ELSE Booked_Hours
    END AS Booked_Hours,

    CASE
      WHEN Vacant_Hours IN (5, 15, 25, 35)
        THEN Vacant_Hours / 10
      ELSE Vacant_Hours
    END AS Vacant_Hours

  FROM `ritzhelper.ritzhelper_dwh.helper_capacity`
)

SELECT

  SUM(Available_Hours)
    AS Total_Available_Hours,

  SUM(Booked_Hours)
    AS Total_Booked_Hours,

  SUM(Vacant_Hours)
    AS Total_Vacant_Hours,

  ROUND(
    SAFE_DIVIDE(
      SUM(Booked_Hours),
      SUM(Available_Hours)
    ) * 100,
    2
  ) AS Utilization_Percentage

FROM cleaned_capacity;

CREATE OR REPLACE VIEW
`ritzhelper.ritzhelper_dwh.v_helper_capacity_by_shift` AS

WITH cleaned_capacity AS (

  SELECT
    Date,
    Helper_ID,
    Shift,

    Available_Hours,

    CASE
      WHEN Booked_Hours IN (5, 15, 25, 35)
        THEN Booked_Hours / 10
      ELSE Booked_Hours
    END AS Booked_Hours,

    CASE
      WHEN Vacant_Hours IN (5, 15, 25, 35)
        THEN Vacant_Hours / 10
      ELSE Vacant_Hours
    END AS Vacant_Hours

  FROM `ritzhelper.ritzhelper_dwh.helper_capacity`
)

SELECT
  Shift,

  SUM(Available_Hours) AS Available_Hours,

  SUM(Booked_Hours) AS Booked_Hours,

  SUM(Vacant_Hours) AS Vacant_Hours,

  ROUND(
    SAFE_DIVIDE(
      SUM(Booked_Hours),
      SUM(Available_Hours)
    ) * 100,
    2
  ) AS Utilization_Percentage

FROM cleaned_capacity

GROUP BY Shift;
