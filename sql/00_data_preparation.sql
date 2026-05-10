--  SECTION 0: LOAD & CLEAN

--  Goal: type-cast raw columns, engineer derived features,
--        and index for query performance.

-- ======================================================================================

-- Three columns are added beyond the raw source:
--   trans_hour  — hour of day (0–23), stored to avoid recomputing on every query
--   age         — calculated to Dec 31 2020 (dataset end date, not today)
--   dist_km     — straight-line distance between cardholder home and merchant,
--                 using the Haversine formula. Stored at load time for performance.



IF OBJECT_ID('transactions', 'U') IS NOT NULL DROP TABLE transactions;

SELECT
    trans_num,
    cc_num,
    CAST(trans_date_trans_time AS DATETIME2)                    AS trans_ts,
    CAST(trans_date_trans_time AS DATE)                         AS trans_date,
    YEAR(CAST(trans_date_trans_time AS DATETIME2))              AS trans_year,
    MONTH(CAST(trans_date_trans_time AS DATETIME2))             AS trans_month,
    DATEPART(HOUR, CAST(trans_date_trans_time AS DATETIME2))    AS trans_hour,
    CAST(dob AS DATE)                                           AS dob,


DATEDIFF(YEAR, CAST(dob AS DATE), '2020-12-31')
        - CASE
            WHEN MONTH(CAST(dob AS DATE)) * 100 + DAY(CAST(dob AS DATE))
               > MONTH('2020-12-31')  * 100 + DAY('2020-12-31')
            THEN 1 ELSE 0
          END                                                   AS age,

           merchant,
    category,
    amt,
    first + ' ' + last                                          AS customer_name,
    gender,
    city,
    state,
    city_pop,
    job,
    lat,
    long,
    merch_lat,
    merch_long,
    is_fraud,

    
    6371 * ACOS(
        CASE
            WHEN COS(RADIANS(lat)) * COS(RADIANS(merch_lat))
               * COS(RADIANS(merch_long) - RADIANS(long))
               + SIN(RADIANS(lat)) * SIN(RADIANS(merch_lat)) > 1
            THEN 1.0
            ELSE COS(RADIANS(lat)) * COS(RADIANS(merch_lat))
               * COS(RADIANS(merch_long) - RADIANS(long))
               + SIN(RADIANS(lat)) * SIN(RADIANS(merch_lat))
        END
    )                                                                  AS dist_km

INTO transactions
FROM (
    SELECT * FROM dbo.fraudTrain    
    UNION ALL
    SELECT * FROM dbo.fraudTest
) combined;


-- Indexes: 
CREATE INDEX idx_txn_cc_num   ON transactions (cc_num);
CREATE INDEX idx_txn_date     ON transactions (trans_date);
CREATE INDEX idx_txn_fraud    ON transactions (is_fraud);
CREATE INDEX idx_txn_category ON transactions (category);


-- Quick sanity check
SELECT
    COUNT(*)                                        AS total_rows,
    COUNT(DISTINCT cc_num)                          AS unique_cards,
    COUNT(DISTINCT merchant)                        AS unique_merchants,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)     AS fraud_rate_pct,
    MIN(trans_date)                                 AS earliest_txn,
    MAX(trans_date)                                 AS latest_txn
FROM transactions;


--: Results: 

--> 1,852,394 rows | 999 cards | 693 merchants | 0.52% fraud rate
--          Jan 2019 – Dec 2020
--> All figures match the known dataset specification.
