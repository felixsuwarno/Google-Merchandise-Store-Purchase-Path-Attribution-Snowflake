WIP : July 26 2026

# Dashvio — E-Commerce Purchase-Path & Attribution-Sensitivity Analysis

Single- vs. Multi-Session Purchase Paths, Purchase-Session Channels, Interpurchase Touchpoints, and Attribution Model & Lookback-Window Sensitivity

<br> E-commerce purchase-path and attribution-sensitivity project using the public Google Analytics 360 sample dataset from the Google Merchandise Store. The analysis examines how many observed sessions visitors take before purchasing, which recorded channels appear on purchase sessions, what touchpoints precede each purchase, and how channel credit changes across attribution rules and lookback windows. The project is built in Snowflake using a RAW → STAGING → ANALYTICS architecture.

<br><br>

➤ **Note on Scope — Read This First :**<br>

Dashvio analyzes observed e-commerce purchase paths and channel credit between August 1, 2016 and August 1, 2017.

The project covers purchasing visitors, sessions leading to observed purchases, recorded purchase-session channels, interpurchase touchpoints, and attribution sensitivity across defined credit rules and lookback windows.

Activity outside this period—including earlier sessions, earlier purchases, and later activity—is outside the project scope. Therefore, “earliest observed” always means earliest available within the project window, not first-ever.

<br><br>

➤ **The Data:**

A single anonymized GA360 sample warehouse holds visitor behavior across two staging tables :
<br>
**STG_SESSIONS** — one row per session (visit-level: channel, device, country, revenue flag)
<br>
**STG_HITS**     — one row per hit (page-level: actions, transactions, revenue)

The data spans August 2016 through August 2017.

<br><br>

➤ **Skills Demonstrated:**

(SQL • Snowflake • Session-Level Analytics • Purchase-Path Reconstruction • Channel Attribution • Window Functions • Interpurchase Windowing • Returning-Customer Analysis • Data Quality Validation • Honest Scope Framing) 

<br><br>

➤ **Core Business Questions:**

**PURCHASE BEHAVIOR** 
<br> 
**BQ01** — What share of purchasing visitors converted in a single session versus multiple sessions? 
<br><br>

**CHANNEL ATTRIBUTION for Multi-session Visitors ONLY** 
<br> 
**BQ02A** — Which channel did they convert on?
<br> 
**BQ02B** — What touchpoints happened before each purchase? 
<br><br>

**Model sensitivity** 
<br>
**BQ03** — Under last-touch and linear attribution, how much transaction and revenue credit does each channel receive?
<br><br>

**Lookback-window sensitivity**
<br>
**BQ04** — How does each channel's credit change between a 30-day window and full observed history (all sessions within the dataset period, not lifetime)?
<br>
<br>

# The Main Report - Key Questions Answered
<br>

### BQ01 — What share of purchasing visitors converted in a single session versus multiple sessions?
<br>

[BQ01B_SINGLE_VS_MULTI_SESSION_SUMMARY.csv](https://github.com/felixsuwarno/Marketing_Attribution-Dashvio-Purchase_Path_Analytics-Snowflake/blob/main/Data_Generated/BQ01B_SINGLE_VS_MULTI_SESSION_SUMMARY.csv)

| SESSION_COUNT_GROUP | REVENUE_SESSION_VISITORS | VISITOR_SHARE |
|---|---|---|
| MULTI_SESSION  | 5,210 | 52.1% |
| SINGLE_SESSION | 4,786 | 47.9% |

**Key Insights :**
- Multi-session purchases are the majority (52.1%), meaning closing-channel and touchpoint analysis in BQ02 applies to most purchasers, not an edge case.
- Session count to conversion ranges up to 138, but that's a magnitude outlier — it doesn't affect the single/multi label, since BQ01 only classifies 1 session vs. 2+.
<br><br>

**BQ02A — Which channel did they convert on?**
<br><br>

**BQ02B — What touchpoints happened before each purchase?**
<br><br>

**BQ03 — Under last-touch and linear attribution, how much transaction and revenue credit does each channel receive?**
<br><br>

**BQ04 — How does each channel's credit change between a 30-day window and full observed history (all sessions within the dataset period, not lifetime)?**
<br><br>













