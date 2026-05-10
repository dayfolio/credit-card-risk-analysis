-- ======================================================================================
-- DATASET LIMITATIONS AND ANALYTICAL CONSTRAINTS
-- ======================================================================================

-- 1. Geographic distance signal is flat. Merchant coordinates were generated
--    near cardholder home addresses, limiting the variation that typically makes 
--    geographic distance a useful fraud signal in real transaction environments. 
--    The Haversine methodology is correct; the signal requires live data to be useful.


-- 2. Single cohort. All 999 cards are active from January 2019 with no
--    acquisition variation or attrition. Real-world cohort analysis would typically 
--    capture customer acquisition, attrition, and lifecycle spending patterns that are 
--    not observable here.


-- 3. Recency days showing 0. Most cardholders remain active through the end of the observation
--    period, compressing recency variation across the portfolio.


-- 4. No credit limit data: Utilisation rate, balance as a percentage of
--    credit limit, is commonly used in both fraud-risk and credit-risk assessment.


-- 5. Fraud loss rate (3.95% of volume) is ~40–60x real-world norms.
--    The synthetic data contains disproportionately large fraud events
--    relative to typical real-world portfolio experience.


-- ======================================================================================
