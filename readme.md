WIP : August 24 2026
# Google Merchandise Store — Purchase-Path & Channel Attribution Analysis

**Multi-Session Purchase Behavior, Converting-Channel Frequency, Prior-Touchpoint Channels, and Last-Touch vs. Linear Attribution Credit**

<br>
*Independent portfolio analysis using obfuscated Google Analytics 360 sample data from the Google Merchandise Store, accessed through BigQuery Public Datasets.*

*Developed under the working codename "Dashvio" — SQL comments and internal notes from development may still reference that name.*

<br>
End-to-end e-commerce analytics project analyzing the public Google Analytics 360 sample dataset from the Google Merchandise Store (Aug 2016–Aug 2017). The analysis covers purchase-path construction, channel touchpoint behavior, and a last-touch vs. linear attribution comparison — built entirely in Snowflake using a **RAW** → **STAGING** → **ANALYTICS** architecture.

<br><br>

➤ **Project Purpose :**<br>

An **attribution project** on this dataset has one problem to solve before any SQL gets written: the dataset only covers twelve months. A visitor's earliest session inside that window is not necessarily their first-ever visit to the store — the window is left-censored. Because the dataset begins in August 2016, it cannot identify a visitor's true first-ever touch. A first-touch model could only be described as first observed touch within the available period — which is a different, weaker claim than true first-touch attribution.

Dashvio works through three connected questions built on GA360's session-grain data :
- **STG_SESSIONS**, one row per session, and
- **STG_HITS**, one row per hit — not yet used, since every question here operates at session grain.

**BQ01** asks how many sessions a purchasing visitor needed to reach their first observed purchase.<br><br>
**BQ02** asks which channel closes purchase sessions for multi-session visitors, and which channels they touch beforehand.<br><br>
**BQ03** compares how last-touch and linear attribution allocate transaction and revenue credit across channels on multi-channel purchase paths.<br><br>

Each table states its grain. Every filter has a reason a business reader can trace back to the question it answers.

<br><br>

➤ **Skills Demonstrated:**

(SQL • Snowflake • Purchase-Path Construction • Window Functions (ROW_NUMBER, LAG) • Multi-Touch Attribution • CTE Pipeline Design • Revenue Conservation Validation • Scope-Honest Analytical Framing)
<br><br>

## Core Business Questions :

**PURCHASE BEHAVIOR** <br>
**BQ01** — How many sessions did purchasing visitors need to reach their first observed purchase — one, or more than one?
<br>

**CHANNEL & TOUCHPOINT ANALYSIS** <br>
**BQ02A** — Across all purchases made by multi-session visitors, which channel closes the purchase session?<br>
**BQ02B** — Which channels do multi-session visitors touch before they buy, and how often?
<br>

**ATTRIBUTION ANALYTICS** <br>
**BQ03** — Under last-touch and linear attribution, how much transaction and revenue credit does each channel receive?
<br>

---

<br>

## The Main Report - Key Questions Answered

<br>

### BQ01 - How many sessions did purchasing visitors need to reach their first observed purchase?

Query logic:
<p align="left">
  <b>
    <a href="SQL/BQ01A_VISITOR_SESSION_COUNT_LABELED.sql">
      BQ01A_VISITOR_SESSION_COUNT_LABELED.sql - Find each visitor's earliest observed revenue session, then count every session from their first observed session up to and including that revenue session
    </a>
  </b>
</p>

<p align="left">
  <b>
    <a href="SQL/BQ01B_SINGLE_VS_MULTI_SESSION_SUMMARY.sql">
      BQ01B_SINGLE_VS_MULTI_SESSION_SUMMARY.sql - Group visitors by SINGLE_SESSION or MULTI_SESSION and calculate each group's share of all purchasing visitors
    </a>
  </b>
</p>

<br>

<p align="left">
  <b>
    <a href="Data_Generated/BQ01B_SINGLE_VS_MULTI_SESSION_SUMMARY.csv">
      Download CSV: BQ01B Single vs. Multi-Session Summary
    </a>
  </b>
</p>

<br>

**Key Insights**
- Out of 9,996 purchasing visitors, 52.1% (5,210 visitors) had more than one observed session before reaching their first observed purchase. 47.9% (4,786 visitors) reached their first observed purchase in their first observed session.
- This measures sessions up to that first observed purchase only. A visitor labeled SINGLE_SESSION here can still have made later purchases in later sessions — BQ01 doesn't track that; it only labels the path to the first one.
- The split is close to even, with a lean toward multi-session — about a 4-point gap.
- "First observed session" is not the same as a visitor's actual first-ever visit. The dataset only shows twelve months, so a visitor who first browsed before August 2016 would still show up here as if their observed history started later than it really did.

<br><br>

---

### BQ02A - Across all purchases made by multi-session visitors, which channel closes the purchase session?

<br>

Query logic:
<p align="left">
  <b>
    <a href="SQL/BQ02A_MULTI_SESSION_CONVERTING_CHANNEL.sql">
      BQ02A_MULTI_SESSION_CONVERTING_CHANNEL.sql - Keep visitors labeled MULTI_SESSION from BQ01A, join them to their revenue session, and count revenue sessions by channel
    </a>
  </b>
</p>

<br>

**Chart**
<p align="left">
  <img src="Charts/BQ02A.png" width="75%">
</p>

<p align="left">
  <b>
    <a href="Data_Generated/BQ02A_MULTI_SESSION_CONVERTING_CHANNEL.csv">
      Download CSV: BQ02A Multi-Session Converting Channel
    </a>
  </b>
</p>

<br>

**Key Insights**
- 6,171 observed revenue sessions belong to visitors classified as multi-session. These include their earliest observed purchase session and any later observed purchase sessions within the dataset. Referral closes 53.5% of them (3,301 sessions).
- Organic Search is second at 26.0% (1,602 sessions), Direct third at 14.6%.
- The remaining four channels — Paid Search, Display, Social, Affiliates — combine for 6.0% of closes.
- Referral and Organic Search together account for 79.45% of the observed purchase sessions belonging to multi-session visitors.

<br><br>

### BQ02B - Which channels do multi-session visitors touch before they buy, and how often?

<br>

Query logic:
<p align="left">
  <b>
    <a href="SQL/BQ02B_PRIOR_TOUCHPOINT_CHANNEL_SUMMARY.sql">
      BQ02B_PRIOR_TOUCHPOINT_CHANNEL_SUMMARY.sql - For each multi-session purchase, look back at the sessions between it and the visitor's previous purchase (or the start of their observed history, for a first purchase), then count those prior sessions by channel
    </a>
  </b>
</p>

<br>

**Chart**
<p align="left">
  <img src="Charts/BQ02B.png" width="75%">
</p>

<p align="left">
  <b>
    <a href="Data_Generated/BQ02B_PRIOR_TOUCHPOINT_CHANNEL_SUMMARY.csv">
      Download CSV: BQ02B Prior Touchpoint Channel Summary
    </a>
  </b>
</p>

<br>

**Key Insights**
- 14,714 prior browse touchpoints happen before multi-session purchases. Referral carries 45.4% of them (6,683 touchpoints), Organic Search 28.2%, Direct 19.1%. Those three channels carry 92.7% of all prior browsing.
- Paid Search (3.5%), Display (3.0%), Social (0.8%), and Affiliates (0.1%) make up the rest.
- Referral represents 53.5% of closing purchase sessions and 45.4% of prior browse touchpoints. This is an 8.1-percentage-point difference between two kinds of session activity. It does not measure Referral's conversion rate because the two percentages use different denominators — 6,171 purchase sessions versus 14,714 prior browse touchpoints.

<br>

#### Business Implications for BQ01 + BQ02

Referral shows the largest gap between its share of closing sessions (53.5%) and its share of prior touchpoints (45.4%) among the three leading channels — an 8.1-point difference. Organic Search and Direct move the other way, with a larger share of prior touchpoints than of closes. This is a compositional pattern, not a conversion rate — the two percentages come from different denominators, so it doesn't show that Referral converts more often than it gets browsed.

Multi-session visitors had more than one observed session before their first observed purchase for 52.1% of purchasing visitors, so the channels a visitor touches beforehand are relevant for more than half the visitors in this dataset.

Actions:

- **If source and medium were retained in the staged data, compare Referral's closing-session share against its prior-touchpoint share at that more granular level** — this would narrow down where the gap sits, not prove what causes it.
- **Treat single-session and multi-session purchasers as two behavior groups with different observed patterns going forward** — BQ01 shows they're close to a 50/50 split, so neither one is the default case.

<br><br>

---

### BQ03 - Under last-touch and linear attribution, how much transaction and revenue credit does each channel receive?

<br>

Query logic:
<p align="left">
  <b>
    <a href="SQL/BQ03A_PURCHASE_PATHS.sql">
      BQ03A_PURCHASE_PATHS.sql - For every purchase a visitor made, assemble the sessions that belong to that purchase's path: from the visitor's previous purchase (or the start of their observed history) up to and including the current purchase
    </a>
  </b>
</p>

<p align="left">
  <b>
    <a href="SQL/BQ03B_PATH_CREDIT_ASSIGNED.sql">
      BQ03B_PATH_CREDIT_ASSIGNED.sql - Drop paths that touched only one distinct channel, since last-touch and linear are forced to agree on those. On the paths that remain, assign linear credit (an equal share of the purchase to every session in the path) and last-touch credit (the full purchase to the closing session, zero to the rest)
    </a>
  </b>
</p>

<p align="left">
  <b>
    <a href="SQL/BQ03C_CHANNEL_ATTRIBUTION_CREDIT.sql">
      BQ03C_CHANNEL_ATTRIBUTION_CREDIT.sql - Sum both credit types by channel
    </a>
  </b>
</p>

<br>

**Chart**
<p align="left">
  <img src="Charts/BQ03.png" width="75%">
</p>

<p align="left">
  <b>
    <a href="Data_Generated/BQ03C_CHANNEL_ATTRIBUTION_CREDIT.csv">
      Download CSV: BQ03C Channel Attribution Credit
    </a>
  </b>
</p>

<br>

**Key Insights**
- BQ03A assembles a path for every purchase — 28,341 path-touchpoint rows. Only 5,857 of those rows survive into BQ03B, belonging to 1,352 purchase sessions across 1,303 visitors — the paths where the two models had an actual choice to make.
- Both models pay out the same total money on those surviving purchases: linear and last-touch each total $247,852.46 in revenue credit. Transaction credits match too — last-touch totals exactly 1,414; linear totals 1,413.999773, a difference from stored decimal precision, not missing credit.
- **Referral, Direct, and Organic Search** have the largest absolute differences in revenue credit between the two models: Referral's last-touch total is $52,408 higher than its linear total; Direct's linear total is $33,210 higher than its last-touch total; Organic Search's linear total is $25,574 higher than its last-touch total. This shows the attribution rule materially changes how revenue is distributed among these three channels — it does not show how many purchases a channel assisted, its causal effect, or its economic value.
- Display's two models move in opposite directions depending on the measure — linear assigns it more transaction credit than last-touch (68.58 vs. 47), but less revenue credit ($12,503 vs. $18,953). Purchase value, not just purchase count, affects which model gives a channel more revenue credit, which is why "assists more" or "closes more" isn't a safe read of these numbers on its own.
- Linear attribution also gives credit to the closing session itself. Under this project's inclusive path boundary, a repeat buyer's purchase session is the closing touchpoint of its own path and the opening touchpoint of the next one, so it can receive linear credit twice. Some of the gap between linear and last-touch totals comes from that path-construction rule, not only from pre-purchase browsing behavior.

<br>

#### Business Implications for BQ03

BQ03 provides attributed revenue under two allocation rules. It cannot calculate ROAS because channel spend is not available. Even with cost data, ROAS should only be calculated for channels whose costs can be mapped consistently to the same channel definitions used in this analysis.













