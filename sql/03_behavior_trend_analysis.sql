-- ======================================================================================
-- BEHAVIOR TREND ANALYSIS
-- ======================================================================================

-- Objective:
-- Analyze changes in customer spending behavior over time using rolling trends and 
-- seasonal activity patterns.

-- Key Questions:
-- 1. Which customers show declining engagement trends?
-- 2. Are there recurring seasonal spending patterns?
-- 3. How does customer activity evolve over time?

-- Business Relevance:
-- Supports churn monitoring, demand forecasting, and proactive customer engagement strategies.

-- ======================================================================================

--  SECTION 3: CUSTOMER COHORT ANALYSIS

--  Business question: How does spending evolve over a cardholder's lifetime?

-- ======================================================================================

-- 3a. Monthly cohort spend matrix

WITH first_seen AS (
    SELECT
        cc_num,
        DATEFROMPARTS(YEAR(MIN(trans_date)), MONTH(MIN(trans_date)), 1) AS cohort_month
    FROM transactions
    GROUP BY cc_num
),
cohort_data AS (
    SELECT
        f.cohort_month,
        DATEFROMPARTS(YEAR(t.trans_date), MONTH(t.trans_date), 1)  AS txn_month,
        t.cc_num,
        SUM(t.amt)                                                  AS spend
    FROM transactions t
    JOIN first_seen f ON t.cc_num = f.cc_num
    WHERE t.is_fraud = 0
    GROUP BY f.cohort_month,
             DATEFROMPARTS(YEAR(t.trans_date), MONTH(t.trans_date), 1),
             t.cc_num
),
cohort_summary AS (
    SELECT
        cohort_month,
        txn_month,
        -- Months since first seen (0 = acquisition month)
        DATEDIFF(MONTH, cohort_month, txn_month)    AS month_number,
        COUNT(DISTINCT cc_num)                      AS active_cards,
        ROUND(SUM(spend), 2)                        AS cohort_spend,
        ROUND(AVG(spend), 2)                        AS avg_spend_per_card
    FROM cohort_data
    GROUP BY cohort_month, txn_month
)
SELECT *
FROM cohort_summary
ORDER BY cohort_month, month_number;


--: Insight:

--> The cohort matrix shows limited long-term engagement decay across the two-year period.
-- In this synthetic dataset, this likely reflects relatively uniform card activity across
-- the observation window. 

--> The more informative pattern is the recurring seasonality: December spend is consistently
-- ~2.7x higher than surrounding months


-- ======================================================================================

-- 3b. Cardholder spend consistency score

WITH monthly_spend AS (
    SELECT
        cc_num,
        customer_name,
        trans_year,
        trans_month,
        SUM(amt) AS monthly_spend
    FROM transactions
    WHERE is_fraud = 0
    GROUP BY cc_num, customer_name, trans_year, trans_month
),
stats AS (
    SELECT
        cc_num,
        customer_name,
        COUNT(*)                        AS active_months,
        ROUND(AVG(monthly_spend), 2)    AS avg_monthly_spend,
        ROUND(STDEV(monthly_spend), 2)  AS stddev_spend,
        ROUND(MIN(monthly_spend), 2)    AS min_monthly_spend,
        ROUND(MAX(monthly_spend), 2)    AS max_monthly_spend
    FROM monthly_spend
    GROUP BY cc_num, customer_name
    HAVING COUNT(*) >= 3
)
SELECT *,
    ROUND(stddev_spend / NULLIF(avg_monthly_spend, 0), 3) AS spend_cv,
    CASE
        WHEN stddev_spend / NULLIF(avg_monthly_spend, 0) < 0.3 THEN 'Consistent'
        WHEN stddev_spend / NULLIF(avg_monthly_spend, 0) < 0.7 THEN 'Variable'
        ELSE 'Erratic'
    END AS spend_pattern
FROM stats
ORDER BY avg_monthly_spend DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY;

--: Insight:

--> The elevated variability observed across top spenders is heavily influenced
-- by recurring December seasonality. The ~2x December spike
-- materially increases the standard deviation for every cardholder.

--> As a result, coefficient-of-variation analysis is more informative when applied 
-- to mid-tier spenders where seasonality is less dominant, or when December is excluded
-- to separate underlying behavioral variability from recurring seasonal effects.


-- ======================================================================================
