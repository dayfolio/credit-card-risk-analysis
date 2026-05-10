-- ======================================================================================
-- CATEGORY RISK ANALYSIS
-- ======================================================================================

-- Objective:
-- Evaluate fraud exposure across transaction categories, transaction amounts, and 
-- timing patterns.

-- Key Questions:
-- 1. Which categories contribute the highest fraud loss?
-- 2. How does fraud concentration vary across amount bands?
-- 3. Are there meaningful time-based fraud patterns?

-- Business Relevance:
-- Helps prioritize fraud monitoring, authentication, and operational controls toward 
-- high-risk activity.

-- ======================================================================================

--  SECTION 2: MERCHANT PERFORMANCE

--  Business question: Which merchant categories are highest value, and which carry
-- the most fraud risk?

-- ======================================================================================

-- 2a. Category scorecard: volume, rate, and dollar loss


SELECT
    category,
    COUNT(*)                                                AS total_txns,
    COUNT(DISTINCT cc_num)                                  AS unique_cards,
    ROUND(SUM(amt), 2)                                      AS gross_volume,
    ROUND(AVG(amt), 2)                                      AS avg_txn_size,
    SUM(is_fraud)                                           AS fraud_txns,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 3)              AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END), 2) AS fraud_dollar_loss
FROM transactions
GROUP BY category
ORDER BY gross_volume DESC;


--: Results: 

--> grocery_pos is the largest category by transaction volume, but its fraud losses 
-- remain proportionally moderate relative to its scale.

--> shopping_net contributes the highest fraud dollar loss ($2.21M) despite lower
-- total volume than grocery_pos. 

--> gas_transport illustrates the floor: despite 188K transactions and a
-- non-trivial fraud rate, losses are only $9K because the average
-- transaction is $63.


--: Insight:

--> Fraud rate and fraud dollar loss tell different stories and both matter.


-- ======================================================================================

-- 2b. Fraud loss as percentage of gross volume — intervention priority

SELECT
    category,
    ROUND(SUM(amt), 2)                                          AS total_volume,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END), 2)   AS fraud_loss,
    ROUND(
        SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END) * 100.0
        / SUM(amt)
    , 2)                                                        AS loss_rate_pct,
    RANK() OVER (
        ORDER BY
            SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END) * 100.0
            / SUM(amt) DESC
    )                                                           AS intervention_priority
FROM transactions
GROUP BY category
ORDER BY loss_rate_pct DESC;


--: Results:

--> shopping_net loses 18.3% of its gross volume to fraud.

--> gas_transport loses 0.08% despite a similar transaction count.


--: Insight:

--> Prioritization changes materially when categories are evaluated by fraud loss relative
-- to transaction volume rather than fraud rate alone.


-- ======================================================================================

-- 2c. Top 20 merchants by volume with their fraud rate

SELECT TOP 20
    merchant,
    category,
    COUNT(*)                                                AS total_txns,
    ROUND(SUM(amt), 2)                                      AS gross_volume,
    ROUND(AVG(amt), 2)                                      AS avg_txn_size,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)              AS fraud_rate_pct
FROM transactions
GROUP BY merchant, category
ORDER BY gross_volume DESC;


--> Merchant-level interpretation is limited due to synthetic naming patterns
-- in the dataset, so category-level insights are more reliable.

-- ======================================================================================

-- 2d. Hour-of-day transaction pattern by category

SELECT
    trans_hour,
    category,
    COUNT(*)                                                AS txn_count,
    ROUND(AVG(amt), 2)                                      AS avg_amt,
    SUM(is_fraud)                                           AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)              AS fraud_rate_pct
FROM transactions
GROUP BY trans_hour, category
ORDER BY trans_hour, category;


--: Results:

--> During daylight hours (roughly 6am to 9pm), every category has a 
-- fraud rate between 0.02% and 0.80%. At hour 22 (10pm), fraud incidence 
-- increases sharply across several categories.

--> grocery_pos jumps to 40.3% fraud rate at 10pm. During the day it runs at 
--  0.18–0.27%.

--> misc_net hits 21.8% at 10pm and 22.9% at 11pm.

--> shopping_net reaches 11.8% at 10pm.

--> shopping_pos, normally 0.06–0.25%, hits 3.97% at 10pm.

--> In this dataset, grocery_pos fraud rates at 10pm are approximately 150x higher than 
-- midday levels.

--: Insights:

--> Fraud incidence varies significantly across time windows, with elevated concentration
-- during late-night hours in several categories.
