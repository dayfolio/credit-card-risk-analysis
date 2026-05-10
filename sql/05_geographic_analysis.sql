-- ======================================================================================
-- GEOGRAPHIC RISK ANALYSIS
-- ======================================================================================

-- Objective:
-- Analyze geographic and distance-based transaction patterns associated with fraud 
-- exposure.

-- Key Questions:
-- 1. How does fraud exposure vary across regions?
-- 2. Are distance-based transaction patterns meaningful?
-- 3. Do population characteristics influence fraud rates?

-- Business Relevance:
-- Supports geographic risk monitoring and identification of regional transaction behavior
-- patterns.

-- ======================================================================================

--  SECTION 5: GEOGRAPHIC RISK ANALYSIS
--  Business question: Which states have disproportionate fraud rates, and does population 
-- density matter?

-- ======================================================================================

-- 5a. State-level fraud summary

SELECT
    state,
    COUNT(*)                                                    AS total_txns,
    COUNT(DISTINCT cc_num)                                      AS unique_cards,
    ROUND(SUM(amt), 2)                                          AS total_volume,
    SUM(is_fraud)                                               AS fraud_txns,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 3)                  AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END), 2)   AS fraud_loss,
    CASE
        WHEN COUNT(*) >= 10000 THEN 'High confidence'
        WHEN COUNT(*) >= 2000  THEN 'Medium confidence'
        WHEN COUNT(*) >= 500   THEN 'Low confidence'
        ELSE 'Indicative only'
    END                                                         AS rate_confidence,
    CASE
        WHEN SUM(is_fraud) * 100.0 / COUNT(*) > 1.0
         AND SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END) > 10000
        THEN 'ELEVATED RISK: rate > 1% AND loss > $10K'
        ELSE ''
    END                                                         AS high_risk_flag
FROM transactions
GROUP BY state
HAVING COUNT(*) >= 200
ORDER BY fraud_rate_pct DESC;
 

--: Results:

--> Rhode Island and Alaska are the only states that exceed both the
-- 1% fraud-rate threshold and $10K fraud-loss threshold in this dataset.


-- ======================================================================================

-- 5b. City population size vs fraud rate

SELECT
    CASE
        WHEN city_pop < 5000   THEN 'Rural (< 5K)'
        WHEN city_pop < 25000  THEN 'Small town (5K-25K)'
        WHEN city_pop < 100000 THEN 'Mid-size (25K-100K)'
        WHEN city_pop < 500000 THEN 'Large city (100K-500K)'
        ELSE 'Metro (500K+)'
    END                                             AS city_size,
    COUNT(*)                                        AS txn_count,
    COUNT(DISTINCT cc_num)                          AS unique_cards,
    ROUND(SUM(amt), 2)                              AS total_volume,
    ROUND(AVG(amt), 2)                              AS avg_txn_amt,
    SUM(is_fraud)                                   AS fraud_txns,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 3)      AS fraud_rate_pct
FROM transactions
GROUP BY
    CASE
        WHEN city_pop < 5000   THEN 'Rural (< 5K)'
        WHEN city_pop < 25000  THEN 'Small town (5K-25K)'
        WHEN city_pop < 100000 THEN 'Mid-size (25K-100K)'
        WHEN city_pop < 500000 THEN 'Large city (100K-500K)'
        ELSE 'Metro (500K+)'
    END
ORDER BY MIN(city_pop);


--: Insight:

--> Fraud-rate variation across city-size bands remains below
-- 0.11 percentage points, making population density a weak signal in this dataset.
-- The observed differences are unlikely to be operationally meaningful
-- within this dataset.
