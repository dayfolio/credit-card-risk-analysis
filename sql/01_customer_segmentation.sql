-- ======================================================================================
-- CUSTOMER SEGMENTATION
-- ======================================================================================
-- Objective:
-- Analyze customer behavior using RFM segmentation, cohort-level analysis, and spend 
-- concentration trends.

-- Key Questions:
-- 1. Which customer groups contribute the highest value?
-- 2. Are there early signs of declining engagement?
-- 3. How does spending behavior vary across cohorts?

-- Business Relevance:
-- Supports customer retention, engagement monitoring, and prioritization of high-value 
-- customer segments.

-- ======================================================================================

-- ======================================================================================

--  SECTION 1: SPEND SEGMENTATION

--  Business question: Who are the most valuable cardholders, and what  does each group need?

-- ======================================================================================

-- 1a. RFM Segmentation
-- Scores every cardholder on Recency, Frequency, and Monetary value.

-- Recency is measured relative to the dataset end date (2020-12-31),not 
-- GETDATE(), so scores are meaningful.


WITH rfm_raw AS (
    SELECT
        cc_num,
        customer_name,
        gender,
        age,
        job,
        MAX(trans_date)                                           AS last_txn_date,
        DATEDIFF(DAY, MAX(trans_date),
            (SELECT MAX(trans_date) FROM transactions))           AS recency_days,
        COUNT(*)                                                  AS frequency,
        SUM(amt)                                                  AS monetary
    FROM transactions
    WHERE is_fraud = 0
    GROUP BY cc_num, customer_name, gender, age, job
),
rfm_scored AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY recency_days DESC)  AS r_score,
        NTILE(4) OVER (ORDER BY frequency ASC)      AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC)       AS m_score
    FROM rfm_raw
),
rfm_segments AS (
    SELECT *,
        r_score + f_score + m_score AS rfm_total,
        CASE
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 2                  THEN 'Loyal'
            WHEN r_score >= 3 AND f_score < 2                   THEN 'Promising'
            WHEN r_score < 2  AND f_score >= 3                  THEN 'At Risk'
            WHEN r_score < 2  AND f_score < 2                   THEN 'Lost'
            ELSE 'Needs Attention'
        END                         AS segment
    FROM rfm_scored
),

sub_segmented AS (
    SELECT *,
        CASE
            WHEN segment != 'Needs Attention'
                THEN segment
            -- Recent but low monetary: engaged but not spending much
            WHEN r_score >= 3 AND m_score <= 2
                THEN 'Active low-spender'
            -- High monetary but gone quiet: big spender churning
            WHEN m_score >= 3 AND r_score <= 2
                THEN 'High-value; gone quiet'
            -- Mid across all three: plateau
            WHEN f_score = 2 AND m_score = 2
                THEN 'Plateau'
            -- Frequent small-ticket buyer
            WHEN r_score = 2 AND f_score >= 2 AND m_score <= 2
                THEN 'Frequent small-ticket'
            ELSE 'Needs Attention: Mixed signals'
        END                                                     AS sub_segment,
        CASE
            WHEN segment != 'Needs Attention'
                THEN 'Standard segment playbook'
            WHEN m_score >= 3 AND r_score <= 2
                THEN 'PRIORITY WIN-BACK — high revenue at risk'
            WHEN r_score >= 3 AND m_score <= 2
                THEN 'Spend-more offer — already engaged'
            WHEN f_score = 2 AND m_score = 2
                THEN 'Monitor - no urgency'
            WHEN r_score = 2 AND f_score >= 2 AND m_score <= 2
                THEN 'Category upgrade offer'
            ELSE 'Queue for manual review'
        END                                                     AS recommended_action
    FROM rfm_segments
),
segment_totals AS (
    SELECT SUM(monetary)                                        AS grand_total
    FROM sub_segmented
)
SELECT
    s.sub_segment,
    s.recommended_action,
    COUNT(*)                                                    AS cardholders,
    ROUND(AVG(s.monetary), 2)                                   AS avg_2yr_spend,
    ROUND(AVG(CAST(s.recency_days AS FLOAT)), 0)                AS avg_recency_days,
    ROUND(AVG(CAST(s.frequency AS FLOAT)), 0)                   AS avg_txn_count,
    ROUND(SUM(s.monetary), 2)                                   AS total_revenue,
    ROUND(SUM(s.monetary) * 100.0 / t.grand_total, 1)          AS pct_of_total_revenue
FROM sub_segmented s
CROSS JOIN segment_totals t
GROUP BY s.sub_segment, s.recommended_action, t.grand_total
ORDER BY total_revenue DESC;
 

--: Results:

--> Champions (222 cardholders) generate $46.6M — 35.9% of total revenue 
-- from 22% of customers.

--> At Risk cardholders (88 people) have the highest average spend per 
-- cardholder at $187,966;higher even than Champions. 
-- These are premium customers who have gone quiet. 


--: Limitations:

--> The recency days are 0;  is expected since synthetic 
-- data has uniform coverage right to the last date.


--: Insights:

--> The top three segments: Champions, High-value gone quiet, and At Risk -
-- together hold 442 cardholders and account for 71% of total revenue.

--> The "High-value; gone quiet" sub-segment represents the clearest
retention priority: 132 cardholders averaging ~$193K in two-year
spend who show reduced recent activity.
  
--> While churn cannot be directly observed in this dataset, the
decline in recent activity suggests elevated retention risk.

--> A targeted win-back offer for this group has the highest revenue-per-card
-- ROI of any retention initiative in the portfolio.

--> At Risk cardholders (avg $188K spend, higher than Champions) follow the
-- same logic, formerly high-value, now quiet. 
  
--> Combined, these two groups account for over $42M in historical
-- revenue associated with customers showing declining engagement.


-- ======================================================================================

-- 1b. Age-band spend profile


SELECT
    CASE
        WHEN age < 25              THEN 'Gen Z (< 25)'
        WHEN age BETWEEN 25 AND 39 THEN 'Millennial (25-39)'
        WHEN age BETWEEN 40 AND 54 THEN 'Gen X (40-54)'
        WHEN age BETWEEN 55 AND 69 THEN 'Boomer (55-69)'
        ELSE 'Silent (70+)'
    END                                             AS age_band,
    gender,
    COUNT(DISTINCT cc_num)                          AS cardholders,
    COUNT(*)                                        AS total_txns,
    ROUND(SUM(amt), 2)                              AS total_spend,
    ROUND(AVG(amt), 2)                              AS avg_txn_amt,
    ROUND(SUM(amt) / COUNT(DISTINCT cc_num), 2)     AS spend_per_cardholder
FROM transactions
WHERE is_fraud = 0
GROUP BY
    CASE
        WHEN age < 25              THEN 'Gen Z (< 25)'
        WHEN age BETWEEN 25 AND 39 THEN 'Millennial (25-39)'
        WHEN age BETWEEN 40 AND 54 THEN 'Gen X (40-54)'
        WHEN age BETWEEN 55 AND 69 THEN 'Boomer (55-69)'
        ELSE 'Silent (70+)'
    END,
    gender
ORDER BY spend_per_cardholder DESC;


--: Results:

--> Gen Z (under 25) ranks 3rd and 4th in spend per cardholder; above
-- Millennial men, Boomer men, and Boomer women. 

--> This is a selection effect: under-25 AmEx cardholders are a narrow, 
-- self-selected group skewed toward high earners and premium family accounts.
-- The Boomer cohort is far broader and more representative, which dilutes 
-- their average.


--: Insights:

--> The business implication: the under-25 demographic is more valuable per
-- card than it appears at population level, and worth monitoring as a 
-- potentially higher-value customer segment than aggregate age-band averages 
-- initially suggest.


-- ======================================================================================

-- 1c. Month-over-month category spend growth

WITH monthly_cat AS (
    SELECT
        trans_year,
        trans_month,
        category,
        SUM(amt) AS monthly_spend
    FROM transactions
    WHERE is_fraud = 0
    GROUP BY trans_year, trans_month, category
),
with_lag AS (
    SELECT *,
        LAG(monthly_spend) OVER (
            PARTITION BY category
            ORDER BY trans_year, trans_month
        ) AS prev_month_spend
    FROM monthly_cat
)
SELECT
    trans_year,
    trans_month,
    category,
    ROUND(monthly_spend, 2)                                         AS monthly_spend,
    ROUND(prev_month_spend, 2)                                      AS prev_month_spend,
    ROUND(
        (monthly_spend - prev_month_spend) * 100.0
        / NULLIF(prev_month_spend, 0),
        1
    )                                                               AS mom_growth_pct
FROM with_lag
ORDER BY trans_year, trans_month, category;


--: Results:

--> All categories show significant December growth
-- (+89% to +126% MoM in this dataset).
  
--> January resets sharply (-60% to -66%). The pattern repeats
-- identically in both 2019 and 2020. Spend builds gradually
-- from February through August, dips in September, and recovers
-- from November before the December peak.


--: Insight: 

--> The December surge is both an opportunity and a risk. On the revenue side, 
-- it is the single most important month; fraud monitoring resources should be 
-- scaled up in November to be ready. On the fraud side, the December spike in
-- transaction volume can make unusual activity harder to distinguish from elevated
-- baseline transaction volume.


-- ======================================================================================

-- 1d. Rolling 3-month spend — individual churn signal


WITH monthly AS (
    SELECT
        cc_num,
        customer_name,
        trans_year,
        trans_month,
        (trans_year - 2019) * 12 + trans_month                 AS month_seq,
        ROUND(SUM(CASE WHEN is_fraud = 0 THEN amt ELSE 0 END), 2) AS legit_spend
    FROM transactions
    GROUP BY cc_num, customer_name, trans_year, trans_month
),
rolling AS (
    SELECT
        cc_num,
        customer_name,
        trans_year,
        trans_month,
        month_seq,
        legit_spend,
        ROUND(AVG(legit_spend) OVER (
            PARTITION BY cc_num
            ORDER BY month_seq
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2)                                                   AS rolling_3m_avg
    FROM monthly
),
with_lag AS (
    SELECT *,
        LAG(rolling_3m_avg) OVER (
            PARTITION BY cc_num ORDER BY month_seq
        )                                                       AS prev_rolling_avg
    FROM rolling
),
trend AS (
    SELECT *,
        ROUND(rolling_3m_avg - prev_rolling_avg, 2)             AS rolling_change,
        CASE
            WHEN prev_rolling_avg IS NULL
                THEN 'Building history'
            WHEN rolling_3m_avg <= prev_rolling_avg * 0.70
                THEN 'URGENT: >30% rolling decline'
            WHEN rolling_3m_avg <= prev_rolling_avg * 0.90
                THEN 'WARNING: 10-30% rolling decline'
            WHEN rolling_3m_avg >= prev_rolling_avg * 1.10
                THEN 'Growing'
            ELSE 'Stable'
        END                                                     AS trend_label
    FROM with_lag
)
SELECT
    cc_num,
    customer_name,
    trans_year,
    trans_month,
    legit_spend                                                 AS current_month_spend,
    rolling_3m_avg,
    prev_rolling_avg,
    rolling_change,
    trend_label,
    RANK() OVER (
        ORDER BY
            CASE trend_label
                WHEN 'URGENT: >30% rolling decline'    THEN 1
                WHEN 'WARNING: 10-30% rolling decline' THEN 2
                ELSE 3
            END,
            rolling_3m_avg DESC
    )                                                           AS retention_priority_rank
FROM trend
WHERE month_seq = (SELECT MAX(month_seq) FROM monthly)
  AND trend_label IN (
        'URGENT: >30% rolling decline',
        'WARNING: 10-30% rolling decline'
  )
ORDER BY retention_priority_rank;

--: Results:

--> 11 cardholders flagged at end of dataset period (Dec 2020):

--> 2 URGENT (>30% rolling decline)
--> 9 WARNING (10-30% decline)


--: Insight:

--> This analysis highlights early signs of declining spend behavior
-- before they become visible in aggregate segment metrics.


-- ======================================================================================
