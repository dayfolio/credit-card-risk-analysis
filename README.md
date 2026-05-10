# Credit Card Fraud & Risk Analysis Using SQL

This project analyzes 1.8M+ credit card transactions to identify behavioral patterns associated with fraud exposure, customer activity, and operational risk. The analysis focuses on signal discovery and business interpretation using SQL techniques commonly applied in financial services and risk analytics.

---

## Objectives

- Identify transaction patterns associated with elevated fraud exposure
- Analyze customer behavior using RFM and trend-based segmentation
- Evaluate fraud concentration across categories, transaction amounts, and time windows
- Assess behavioral indicators such as transaction velocity and spending anomalies
- Translate analytical findings into operational and business recommendations

---

## Dataset

Source: Kaggle Credit Card Transactions Dataset  
Link: kaggle.com/datasets/kartik2112/fraud-detection

- ~1.85 million transactions
- 999 cardholders
- 2019–2020 transaction history
- Overall fraud rate: ~0.52%

---

## Key Analyses

### Customer Segmentation
- RFM analysis
- Rolling spend trend analysis
- Cohort-level behavior analysis

### Fraud Risk Analysis
- Fraud rate vs fraud loss comparison
- Category-level risk exposure
- Amount-band fraud concentration
- Time-of-day fraud patterns

### Behavioral Risk Signals
- Transaction velocity analysis
- Personal baseline deviation (percentile-based)
- Context-aware risk conditions

### Geographic Analysis
- State-level fraud patterns
- Distance-based transaction analysis

---

## Key Insights

- Fraud exposure is concentrated in high-value and online transactions
- Transaction velocity alone produces high false-positive rates without behavioral context
- A small customer segment contributes a disproportionate share of total revenue
- Seasonal transaction spikes significantly increase operational and fraud-monitoring requirements

---

## Tools & Techniques

- SQL Server
- Common Table Expressions (CTEs)
- Window Functions
- Rolling Averages
- Percentile Analysis
- RFM Segmentation
- Haversine Distance Calculation

---

## Repository Structure

credit-card-risk-analysis/
│
├── README.md
│
├── data/
│   └── dataset_source.txt
│
├── sql/
│   ├── 00_data_preparation.sql

│   ├── 01_customer_segmentation.sql

│   ├── 02_category_risk_analysis.sql
│   ├── 03_behavior_trend_analysis.sql
│   ├── 04_velocity_analysis.sql
│   ├── 05_geographic_analysis.sql
│   ├── 06_ad_hoc_analytical_queries.sql
│   └── 07_dataset_limitations.sql
│
├── outputs/
│   ├── screenshots/
│   │   ├── rfm_segmentation.png
│   │   ├── category_risk_analysis.png
│   │   ├── amount_band_fraud_rates.png
│   │   ├── velocity_analysis.png
│   │   ├── geographic_risk_analysis.png
│   │   └── seasonal_spending_trends.png
│   │
│   └── summary_tables/
│       ├── rfm_summary.csv
│       ├── category_risk_summary.csv
│       ├── velocity_flags_summary.csv
│       └── geographic_risk_summary.csv
│
└── docs/
    └── project_summary.md
