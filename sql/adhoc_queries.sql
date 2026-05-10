-- ======================================================================================
-- AD HOC ANALYTICAL QUERIES
-- ======================================================================================

-- Objective:
-- Conduct targeted exploratory analyses to investigate specific
-- fraud, customer, and operational risk questions.

-- Business Relevance:
-- Reflects the ad hoc investigative workflow commonly used in
-- fraud analytics and risk-monitoring environments.


-- ======================================================================================

-- Q: How frequently do fraud transactions occur shortly after
-- high-value legitimate transactions on the same card?

WITH large_legit AS (
    SELECT cc_num, trans_ts, amt
    FROM transactions
    WHERE is_fraud = 0 AND amt > 500
),
fraud_txns AS (
    SELECT cc_num, trans_ts
    FROM transactions
    WHERE is_fraud = 1
)
SELECT TOP 50
    l.cc_num,
    l.trans_ts                                                  AS legit_txn_time,
    l.amt                                                       AS legit_amt,
    f.trans_ts                                                  AS fraud_txn_time,
    ROUND(DATEDIFF(SECOND, l.trans_ts, f.trans_ts) / 3600.0, 2) AS hours_between
FROM large_legit l
JOIN fraud_txns f ON l.cc_num = f.cc_num
WHERE f.trans_ts BETWEEN l.trans_ts AND DATEADD(HOUR, 24, l.trans_ts)
ORDER BY hours_between ASC;
 

-- ======================================================================================

-- Q: Which categories experienced the largest month-over-month
-- increases in fraud rate?

WITH monthly_fraud AS (
    SELECT
        category,
        trans_year,
        trans_month,
        ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 3) AS fraud_rate
    FROM transactions
    GROUP BY category, trans_year, trans_month
),
with_lag AS (
    SELECT *,
        LAG(fraud_rate) OVER (
            PARTITION BY category ORDER BY trans_year, trans_month
        ) AS prev_fraud_rate
    FROM monthly_fraud
)
SELECT TOP 10
    category,
    trans_year,
    trans_month,
    fraud_rate,
    ROUND(fraud_rate - prev_fraud_rate, 3) AS fraud_rate_change
FROM with_lag
WHERE prev_fraud_rate IS NOT NULL
ORDER BY fraud_rate_change DESC;


-- ======================================================================================

-- Q: Top 5 states where fraud accounts for more than 1% of transactions
-- AND fraud loss exceeds $10,000.

SELECT TOP 5
    state,
    SUM(is_fraud)                                               AS fraud_txns,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 3)                  AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END), 2)   AS fraud_loss
FROM transactions
GROUP BY state
HAVING
    SUM(is_fraud) * 100.0 / COUNT(*) > 1
    AND SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END) > 10000
ORDER BY fraud_loss DESC;


--: Insight:

--> The combination identifies states where fraud is both statistically elevated and financially material.

--> Only two states qualify, confirming that elevated fraud exposure is concentrated within a small subset
-- of states rather than distributed evenly across the portfolio.
 
