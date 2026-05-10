-- ==========================================================================================
-- TRANSACTION VELOCITY ANALYSIS
-- ==========================================================================================


-- Objective:
-- Evaluate transaction velocity and behavioral anomalies associated with elevated fraud exposure.

-- Key Questions:
-- 1. Which high-activity patterns are associated with fraud?
-- 2. How can behavioral context reduce false positives?
-- 3. Which transaction conditions indicate elevated risk?

-- Business Relevance:
-- Supports monitoring of abnormal transaction activity and evaluation of high-risk behavioral patterns.

-- ==========================================================================================

--  SECTION 4: FRAUD DETECTION SIGNALS
--  Business question: What behavioral signals are most strongly associated with elevated fraud risk?

-- ==========================================================================================

-- 4a. Fraud rate by geo distance

SELECT
    CASE
        WHEN dist_km < 30  THEN '< 30 km (local)'
        WHEN dist_km < 60  THEN '30-60 km'
        WHEN dist_km < 100 THEN '60-100 km'
        ELSE '> 100 km (remote)'
    END                                             AS distance_band,
    COUNT(*)                                        AS txn_count,
    ROUND(AVG(amt), 2)                              AS avg_amt,
    SUM(is_fraud)                                   AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 3)      AS fraud_rate_pct
FROM transactions
GROUP BY
    CASE
        WHEN dist_km < 30  THEN '< 30 km (local)'
        WHEN dist_km < 60  THEN '30-60 km'
        WHEN dist_km < 100 THEN '60-100 km'
        ELSE '> 100 km (remote)'
    END
ORDER BY MIN(dist_km);


--: Insight:

--> The fraud rate is essentially flat across all distance bands;
-- a known limitation of this dataset. Merchant coordinates were
-- generated geographically close to cardholder home addresses,
-- limiting the usefulness of distance as a differentiating fraud signal.


-- ======================================================================================

-- 4b. Transaction velocity: Layered rule system
-- (1) transaction distributions are zero-inflated
-- (2) high-activity cardholders have a naturally high baseline


-- Layer 1 (absolute rules): flags extreme velocity, extreme spend,
--   merchant scatter, and night-time bursts regardless of cardholder history.

WITH hourly AS (
    SELECT
        cc_num,
        trans_date,
        category,
        DATEPART(HOUR, trans_ts)                                AS txn_hour,
        COUNT(*)                                                AS txns_in_hour,
        ROUND(SUM(amt), 2)                                      AS spend_in_hour,
        SUM(is_fraud)                                           AS fraud_in_hour,
        COUNT(DISTINCT merchant)                                AS distinct_merchants,
        -- Track whether any in-person (non-net) txns exist this hour
        SUM(CASE WHEN category NOT LIKE '%_net' THEN 1 ELSE 0 END) AS inperson_txns
    FROM transactions
    GROUP BY cc_num, category, trans_date, DATEPART(HOUR, trans_ts)
),


absolute_flags AS (
SELECT cc_num, trans_date, txn_hour, category
FROM hourly
WHERE txns_in_hour >= 8
   OR spend_in_hour >= 3000
   OR (distinct_merchants >= 5 AND inperson_txns >= 5)
   OR (txn_hour BETWEEN 22 AND 23 AND txns_in_hour >= 4)
   ),

-- Layer 2: Recent personal baseline
-- Adapts to lifestyle changes
-- flags transactions that exceed a card's own 90th percentile spend or 
-- velocity over the past 90 days.
-- Only activates for cards with 30+ days of history (fixes cold start).
-- Uses only the last 90 days (fixes non-stationarity).
-- PERCENTILE_CONT makes no distribution assumption (fixes zero-inflation).

card_meta AS (
    SELECT cc_num,
        MIN(trans_date)                                         AS first_seen,
        MAX(trans_date)                                         AS last_seen,
        DATEDIFF(DAY, MIN(trans_date), MAX(trans_date))         AS history_days
    FROM transactions
    GROUP BY cc_num
),
recent_p90 AS (
    SELECT DISTINCT
        h.cc_num,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY h.txns_in_hour)
            OVER (PARTITION BY h.cc_num)                        AS p90_txns,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY h.spend_in_hour)
            OVER (PARTITION BY h.cc_num)                        AS p90_spend
    FROM hourly h
    JOIN card_meta m ON h.cc_num = m.cc_num
    WHERE h.trans_date >= DATEADD(DAY, -90, m.last_seen)
      AND m.history_days >= 30   
),

personal_baseline AS (
SELECT h.cc_num, h.trans_date, h.txn_hour, h.category
    FROM hourly h
    JOIN recent_p90 p ON h.cc_num = p.cc_num
    WHERE h.txns_in_hour > p.p90_txns
       OR h.spend_in_hour > p.p90_spend * 2
),
 
 -- Layer 3: Population context
 -- Handles high-activity users
 -- applies the population-level fraud rate for that category 
 -- at that hour as a risk modifier.

context_risk AS (
    SELECT
        category,
        DATEPART(HOUR, trans_ts)                                AS txn_hour,
        ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)              AS population_fraud_rate,
        CASE
            WHEN ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2) >= 10
            THEN 'HIGH RISK CONTEXT'
            WHEN ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2) >= 2
            THEN 'ELEVATED CONTEXT'
            ELSE 'NORMAL CONTEXT'
        END                                                     AS context_label
    FROM transactions
    GROUP BY category, DATEPART(HOUR, trans_ts)
),
layer3 AS (
    SELECT h.cc_num, h.trans_date, h.txn_hour, h.category
    FROM hourly h
    JOIN context_risk c ON h.category = c.category AND h.txn_hour = c.txn_hour
    WHERE c.context_label IN ('HIGH RISK CONTEXT', 'ELEVATED CONTEXT')
)

SELECT
    h.cc_num,
    h.trans_date,
    h.txn_hour,
    h.category,
    h.txns_in_hour,
    h.spend_in_hour,
    h.fraud_in_hour,

    -- Layer 1: individual flags
    CASE WHEN h.txns_in_hour >= 8                                       THEN 1 ELSE 0 END  AS flag_extreme_velocity,
    CASE WHEN h.spend_in_hour >= 3000                                   THEN 1 ELSE 0 END  AS flag_extreme_spend,
    CASE WHEN h.distinct_merchants >= 5 AND h.inperson_txns >= 5        THEN 1 ELSE 0 END  AS flag_merchant_scatter,
    CASE WHEN h.txn_hour BETWEEN 22 AND 23 AND h.txns_in_hour >= 4      THEN 1 ELSE 0 END  AS flag_night_burst,

    -- Layer 1: composite score
    (CASE WHEN h.txns_in_hour >= 8                                      THEN 1 ELSE 0 END +
     CASE WHEN h.spend_in_hour >= 3000                                  THEN 1 ELSE 0 END +
     CASE WHEN h.distinct_merchants >= 5 AND h.inperson_txns >= 5       THEN 1 ELSE 0 END +
     CASE WHEN h.txn_hour BETWEEN 22 AND 23 AND h.txns_in_hour >= 4     THEN 1 ELSE 0 END
    )                                                                   AS rules_triggered,

    -- Layer 2: personal baseline context
    p.p90_txns                                                          AS card_p90_txns,
    p.p90_spend                                                         AS card_p90_spend,

    -- Layer 3: population context
    c.population_fraud_rate                                             AS context_fraud_rate_pct,
    c.context_label,

    CASE WHEN h.fraud_in_hour > 0 THEN 'CONFIRMED FRAUD' ELSE 'UNCONFIRMED ALERT' END      AS status

FROM hourly h
JOIN absolute_flags        l1 ON h.cc_num    = l1.cc_num
                     AND h.trans_date = l1.trans_date
                     AND h.txn_hour   = l1.txn_hour
                     AND h.category   = l1.category
JOIN personal_baseline        l2 ON h.cc_num    = l2.cc_num
                     AND h.trans_date = l2.trans_date
                     AND h.txn_hour   = l2.txn_hour
                     AND h.category   = l2.category
JOIN layer3        l3 ON h.cc_num    = l3.cc_num
                     AND h.trans_date = l3.trans_date
                     AND h.txn_hour   = l3.txn_hour
                     AND h.category   = l3.category
JOIN recent_p90    p  ON h.cc_num    = p.cc_num
JOIN context_risk  c  ON h.category  = c.category
                     AND h.txn_hour   = c.txn_hour
ORDER BY rules_triggered DESC, h.spend_in_hour DESC;


--: Results:

--> 67 card-hour combinations pass all three layers.
--> All flagged cases occur within HIGH RISK CONTEXT windows and are associated
-- with confirmed fraud transactions in the dataset. 

--: Insight:

--> The confirmed fraud cases share three characteristics simultaneously:
-- multiple transactions in one hour, high spend, and a night-time window
-- in a high-risk category. No individual condition is independently reliable; the strongest signal
-- emerges when multiple behavioral and contextual conditions align.


-- ======================================================================================

-- 4c. Fraud rate by amount band

WITH band_counts AS (
    SELECT
        CASE
            WHEN amt < 10   THEN '1: < $10'
            WHEN amt < 50   THEN '2: $10-50'
            WHEN amt < 200  THEN '3: $50-200 (safe zone)'
            WHEN amt < 500  THEN '4: $200-500'
            WHEN amt < 1000 THEN '5: $500-1000'
            ELSE             '6: > $1000'
        END                                                     AS band,
        COUNT(*)                                                AS txn_count,
        SUM(is_fraud)                                           AS actual_fraud
    FROM transactions
    GROUP BY
        CASE WHEN amt < 10 THEN '1: < $10' WHEN amt < 50 THEN '2: $10-50'
             WHEN amt < 200 THEN '3: $50-200 (safe zone)'
             WHEN amt < 500 THEN '4: $200-500'
             WHEN amt < 1000 THEN '5: $500-1000' ELSE '6: > $1000' END
),
portfolio_rate AS (
    SELECT ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4) AS overall_rate
    FROM transactions
)
SELECT
    b.band,
    b.txn_count,
    b.actual_fraud,
    ROUND(b.actual_fraud * 100.0 / b.txn_count, 3)             AS actual_fraud_rate_pct,
    ROUND(b.txn_count * p.overall_rate / 100.0, 0)             AS expected_if_random,
    ROUND(b.txn_count * p.overall_rate / 100.0, 0)
        - b.actual_fraud                                        AS fraud_deficit,
    ROUND((1.0 - b.actual_fraud /
        NULLIF(b.txn_count * p.overall_rate / 100.0, 0)) * 100.0, 0) AS pct_below_expected
FROM band_counts b
CROSS JOIN portfolio_rate p
ORDER BY b.band;
 

--: Insight:

--> The $50–200 band contains 43% of all transactions but only 267 fraud
-- cases; 94% fewer fraud cases than expected under the portfolio-wide average fraud rate.

--> Above $500, fraud rates jump to 21–22%, carrying 41–42x the expected
-- fraud count. Fraud concentration increases materially in higher-value transaction bands: 
-- the $500–$1,000 band has just 16,189 transactions but accounts for 3,458 fraud cases.


-- ======================================================================================

-- 4d. RFM segment × fraud exposure cross-analysis
-- Which segments are most targeted by fraudsters?

WITH rfm_raw AS (
    SELECT
        cc_num,
        DATEDIFF(DAY, MAX(trans_date),
            (SELECT MAX(trans_date) FROM transactions))         AS recency_days,
        COUNT(*)                                                AS frequency,
        SUM(amt)                                                AS monetary
    FROM transactions
    WHERE is_fraud = 0
    GROUP BY cc_num
),
rfm_scored AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY recency_days DESC)              AS r_score,
        NTILE(4) OVER (ORDER BY frequency ASC)                  AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC)                   AS m_score
    FROM rfm_raw
),
rfm_labelled AS (
    SELECT cc_num, monetary,
        CASE
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 2                  THEN 'Loyal'
            WHEN r_score >= 3 AND f_score < 2                   THEN 'Promising'
            WHEN r_score < 2  AND f_score >= 3                  THEN 'At Risk'
            WHEN r_score < 2  AND f_score < 2                   THEN 'Lost'
            ELSE 'Needs Attention'
        END                                                     AS segment
    FROM rfm_scored
),
card_fraud AS (
    SELECT cc_num,
        COUNT(*)                                                AS fraud_txns,
        ROUND(SUM(amt), 2)                                      AS fraud_loss
    FROM transactions
    WHERE is_fraud = 1
    GROUP BY cc_num
)
SELECT
    r.segment,
    COUNT(DISTINCT r.cc_num)                                    AS total_cards,
    COUNT(DISTINCT f.cc_num)                                    AS cards_hit_by_fraud,
    ROUND(COUNT(DISTINCT f.cc_num) * 100.0
        / COUNT(DISTINCT r.cc_num), 1)                          AS pct_cards_hit,
    ROUND(SUM(ISNULL(f.fraud_loss, 0)), 2)                      AS total_fraud_loss,
    ROUND(AVG(ISNULL(f.fraud_loss, 0)), 2)                      AS avg_fraud_loss_per_card,
    ROUND(AVG(r.monetary), 2)                                   AS avg_legit_spend_per_card,
    ROUND(SUM(ISNULL(f.fraud_loss, 0))
        / NULLIF(SUM(r.monetary), 0) * 100.0, 2)               AS fraud_as_pct_of_segment_revenue
FROM rfm_labelled r
LEFT JOIN card_fraud f ON r.cc_num = f.cc_num
GROUP BY r.segment
ORDER BY total_fraud_loss DESC;


--: Insight:

--> Fraud exposure appears across all customer segments with relatively 
-- limited variation in card-level incidence.

--> The key differentiator is not who gets targeted but how much damage
-- fraud causes as a proportion of their legitimate spend.

--> Promising and Lost segments show fraud consuming 10% of their revenue,
-- disproportionately high relative to their low absolute spend levels.
-- This matters because fraud losses represent a disproportionately larger
-- share of legitimate spend for lower-value segments, potentially increasing 
-- post-incident disengagement risk.


-- ======================================================================================
