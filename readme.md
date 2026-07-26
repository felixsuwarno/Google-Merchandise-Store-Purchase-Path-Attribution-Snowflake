# Dashvio — E-Commerce Purchase-Path & Channel Attribution Analytics

Single vs Multi-Session Purchases, Converting-Channel Attribution, Interpurchase Touchpoint Paths, and Returning-Customer Analysis

<br> End-to-end e-commerce attribution project analyzing the Google Analytics 360 sample dataset from the Google Merchandise Store — a real, anonymized session-and-hit log of visitor behavior. The analysis covers how many sessions visitors take before purchasing, which channels they convert on, and what touchpoints precede each purchase — built entirely in Snowflake using a **RAW** → **STAGING** → **ANALYTICS** architecture.

<br><br>

➤ Note on Scope — Read This First :<br>

The GA360 sample covers a fixed window (August 2016 through August 2017). A visitor's earliest observed session is only their first session inside that window, not their first-ever visit. Cookies that predate the window are invisible.

This project therefore does not claim to measure true customer acquisition or lifetime first-touch. Every business question is scoped to observed behavior inside the window, and every table says so. Reconstructing a complete acquisition path from a fixed-window session log is not possible, so the project is built to answer only what the data can actually support.

<br><br>

➤ **Project Purpose :**<br>

Marketing attribution is usually sold as one clean number — "this channel drove the sale." Real session data does not cooperate. A visitor arrives on one channel, leaves, comes back on another, browses, buys, then comes back weeks later and buys again. The question "which channel gets credit" hides several smaller questions underneath it.

Dashvio treats those smaller questions as one connected problem.

A single anonymized GA360 sample warehouse holds visitor behavior across two staging tables :

STG_SESSIONS — one row per session (visit-level: channel, device, country, revenue flag)
STG_HITS — one row per hit (page-level: actions, transactions, revenue)

The data spans August 2016 through August 2017.

Each business question works through the same underlying problem — how do visitors actually reach a purchase — from a different angle.

BQ01 sits at the visitor layer — of everyone who purchased, how many bought in a single session versus across multiple sessions. This sizes the multi-session population the rest of the project depends on. <br><br> BQ02A and BQ02B sit at the path layer — for multi-session purchasers, which channel they converted on, and what touchpoints preceded each purchase inside its interpurchase window. <br><br>

The project is built in Snowflake. Two staging tables, three schema layers, one analytics table per business question. Every table states its grain. Every filter has a reason. Every attribution claim is scoped to observed behavior, never lifetime.

<br><br>

➤ Skills Demonstrated:

(SQL • Snowflake • Session-Level Analytics • Purchase-Path Reconstruction • Channel Attribution • Window Functions • Interpurchase Windowing • Returning-Customer Analysis • Data Quality Validation • Honest Scope Framing) <br><br>

Core Business Questions :

PURCHASE BEHAVIOR <br> BQ01 — What share of purchasing visitors converted in a single session versus multiple sessions? <br>

CHANNEL ATTRIBUTION <br> BQ02A — For multi-session visitors, which channel did they convert on?<br> BQ02B — For multi-session visitors, what touchpoints happened before each purchase, and how many times had they already purchased? <br>

<br>
The Main Report - Key Questions Answered
<br>
BQ01 - What share of purchasing visitors converted in a single session versus multiple sessions?

Query logic:

<p align="left"> <b> <a href="SQL/BQ01_SINGLE_VS_MULTI_SESSION_SUMMARY.sql"> BQ01_SINGLE_VS_MULTI_SESSION_SUMMARY.sql - Count each purchasing visitor's sessions up to their first revenue session, label single vs multi, and summarize the share </a> </b> </p> <br>

The output classifies every purchasing visitor as single-session or multi-session, based on how many observed sessions they had from their first observed session up to and including their earliest observed revenue session.

<p align="left"> <b> <a href="Data_Generated/BQ01_SINGLE_VS_MULTI_SESSION_SUMMARY.csv"> Download CSV: BQ01 Single vs Multi-Session Summary </a> </b> </p> <br>

Key Insights

[ RUN BQ01 AND FILL IN: X% of purchasing visitors bought in a single observed session; Y% took multiple sessions. ]
[ FILL IN: what the single-session share means — how much revenue closes on first contact versus needs repeat visits. ]
Scope note: "first purchase" here means earliest observed revenue session, not first-ever purchase.

<br><br>

BQ02A - For multi-session visitors, which channel did they convert on?
<br>

Query logic:

<p align="left"> <b> <a href="SQL/BQ02A_MULTI_SESSION_CONVERTING_CHANNEL.sql"> BQ02A_MULTI_SESSION_CONVERTING_CHANNEL.sql - For multi-session purchasers, count purchase sessions by the channel they converted on </a> </b> </p> <br>

The output ranks channels by how often a multi-session visitor's purchase happened on that channel. This is the closing channel — the last-touch view of where purchases land.

<p align="left"> <b> <a href="Data_Generated/BQ02A_MULTI_SESSION_CONVERTING_CHANNEL.csv"> Download CSV: BQ02A Converting Channel Summary </a> </b> </p> <br>

Key Insights

[ RUN BQ02A AND FILL IN: which channel closes the most multi-session purchases, with its share. ]
[ FILL IN: whether Direct over-indexes as a closing channel — the classic last-touch bias, where returning visitors type the URL directly and Direct collects credit it did not earn. ]
Scope note: this is closing-channel frequency, not fractional attribution credit.

<br><br>

BQ02B - For multi-session visitors, what touchpoints happened before each purchase?
<br>

Query logic:

<p align="left"> <b> <a href="SQL/BQ02B_MULTI_SESSION_PRIOR_TOUCHPOINTS.sql"> BQ02B_MULTI_SESSION_PRIOR_TOUCHPOINTS.sql - Window each purchase against the visitor's previous purchase, list the touchpoints in between, and tally prior purchases </a> </b> </p> <br>

For every purchase by a multi-session visitor, this reconstructs the path of touchpoints that preceded it — browses shown by channel, and the immediately prior purchase shown as PURCHASE. Each purchase's window runs from the previous purchase (inclusive) up to just before the current one, so no browse is ever counted against two purchases. A separate cumulative count records how many times the visitor had already purchased.

<p align="left"> <b> <a href="Data_Generated/BQ02B_MULTI_SESSION_PRIOR_TOUCHPOINTS.csv"> Download CSV: BQ02B Prior Touchpoints per Purchase </a> </b> </p> <br>

Key Insights

BQ02B produced 6,171 purchase-paths from multi-session visitors, one row per purchase.
About 15.6% of these paths were repeat purchases — the visitor had already bought within the observed window. The remaining ~84% were the visitor's first observed purchase.
The prior-purchase count tapers realistically: most repeat buyers had bought once before, with a long tail up to 15 prior purchases for the heaviest returning customer.
Referral and Organic Search dominate the prior-touchpoint paths, often appearing many times in a single path before a purchase closes.
Scope note: the returning-customer share is a floor — a customer whose first purchase predates the window looks first-time here. It is also a share of purchase-paths, not of distinct customers, since a repeat buyer contributes multiple rows.
<br>
Business Implications for BQ02A + BQ02B

Dashvio's attribution view should separate where purchases close (BQ02A) from what led up to them (BQ02B), because the closing channel systematically over-credits low-funnel channels for customers who were already engaged. The touchpoint paths show that many purchases follow long browse sequences, and for returning customers a prior purchase — so budget decisions based on closing channel alone would starve the upper-funnel channels doing the real work.

Actions:

Do not read the closing channel as the acquiring channel. BQ02A shows where purchases land; BQ02B shows the path that got them there. Fund the channels that appear repeatedly in paths, not only the ones that close.
Treat returning customers separately. Any purchase with a prior PURCHASE in its path is a retention event, not an acquisition event. Blending the two inflates the apparent performance of low-funnel channels.
Watch the heavy-path outliers. A minority of paths carry dozens of touchpoints, up to 137 sessions before a single purchase. Decide whether these are genuine high-consideration buyers or bot/referral-spam traffic before weighting anything by touchpoint count downstream.

<br><br>

<br>
Architecture & Scope Notes
RAW → STAGING → ANALYTICS in Snowflake. Every Dashvio script begins with USE DATABASE DASHVIO; and the appropriate schema declaration.
Grain is stated on every table. Session-grain throughout, because attribution and budgeting decisions are made on channels and touchpoints, not on basket size — a multi-transaction session is still one visit on one channel.
Every table carries its scope caveat. The observed-window limitation is written into the SQL headers, not hidden in a footnote.
Grain validation before locking. BQ02B ships with a validation query confirming no visitor has two sessions at the same timestamp, since timestamps order the touchpoint paths.
