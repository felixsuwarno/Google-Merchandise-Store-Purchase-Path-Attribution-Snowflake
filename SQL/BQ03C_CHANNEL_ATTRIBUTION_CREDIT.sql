USE DATABASE DASHVIO;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ03  (Table 3 of 3: BQ03C_CHANNEL_ATTRIBUTION_CREDIT)
--
-- Business question:
-- "Under last-touch and linear attribution, how much transaction and
--  revenue credit does each channel receive?"
--
-- This is the table that answers the business question. BQ03B assigned credit
-- to each surviving session under both models; this table adds that credit up
-- by channel, so each channel has one linear total and one last-touch total
-- for transactions and for revenue.
--
-- There is one result, not a comparison of scopes. The paths where last-touch
-- and linear are forced to agree were removed in BQ03B, so every row that
-- reaches here comes from a path where the two models had a real choice. The
-- gap between a channel's linear total and its last-touch total is the number
-- a budget decision reads: a channel with more linear than last-touch is one
-- last-touch under-credits, because it assists more purchases than it closes.
--
-- How this differs from GA4 and Adobe CJA:
-- GA4's old Model Comparison view and Adobe CJA both report attribution across
-- every conversion path, single-channel paths included, and let the reader
-- compare models side by side over that full set. This table reports only the
-- multi-channel subset, on purpose, for the budget-decision reason above. It
-- is therefore not a drop-in match for a GA4 or Adobe channel report; it is a
-- narrower, decision-focused cut. GA4 no longer offers linear attribution in
-- its interface at all (removed November 2023), so this specific two-model
-- comparison is a custom computation, not something GA4 produces today.
--
-- Output: one row per channel, with four credit totals.
--
-- Definitions:
--   - Direct is credited literally. No last-non-direct rewrite. GA4 and Adobe
--     often reassign direct traffic to the previous non-direct channel; this
--     project does not, so a channel's totals here are its own, not inflated
--     by direct sessions folded into it.
--   - Every row comes from a path with more than one distinct channel.
--     Single-session purchases and same-channel repeat paths do not appear;
--     they were removed in BQ03B before credit was calculated.
--   - Totals cover purchase paths observed between 2016-08-01 and 2017-08-01.
--     They describe attribution inside this window, not lifetime attribution,
--     and they are not the store's total revenue: single-channel paths are
--     excluded by design.
-- ============================================================


-- CREATE OR REPLACE TABLE DASHVIO.ANALYTICS.BQ03C_CHANNEL_ATTRIBUTION_CREDIT AS


-- ------------------------------------------------------------
-- Step 1 - Keep the channel and the credit amounts
-- CTE name: purchase_touchpoint_credit_filtered
--
-- The answer groups credit by channel, so only two things matter from here
-- on: which channel earned the credit, and how much it earned. Both live in
-- BQ03B_PATH_CREDIT_ASSIGNED, which already holds only the touchpoints of
-- multi-channel paths.
--
-- This CTE keeps TOUCHPOINT_CHANNEL_GROUPING and the four credit columns: the
-- two linear credit columns and the two last-touch credit columns.
--
-- The visitor, purchase, and session identities are dropped. Once credit has
-- been assigned, who earned it and which path it came from no longer changes
-- the totals.
--
-- No rows are removed. Once this is done, the next CTE can add these rows up
-- by channel.
-- ------------------------------------------------------------
WITH purchase_touchpoint_credit_filtered AS
(
    SELECT
        TOUCHPOINT_CHANNEL_GROUPING,
        LINEAR_CREDIT_TRANSACTIONS,
        LINEAR_CREDIT_REVENUE,
        LAST_TOUCH_CREDIT_TRANSACTIONS,
        LAST_TOUCH_CREDIT_REVENUE
    FROM DASHVIO.ANALYTICS.BQ03B_PATH_CREDIT_ASSIGNED
),


-- ------------------------------------------------------------
-- Step 2 - Add up each channel's credit across the surviving purchase paths
-- CTE name: channel_attribution_credit_aggregated_metrics
--
-- This is the answer to the business question: what each channel is worth,
-- under both models, on the purchases where the models had a real choice to
-- make. The channel and the four credit amounts live in
-- purchase_touchpoint_credit_filtered from Step 1.
--
-- Rows are grouped by TOUCHPOINT_CHANNEL_GROUPING, and the four credit
-- columns are added within each group. A channel that assisted eight hundred
-- multi-channel purchases collects linear credit from all eight hundred, and
-- last-touch credit from whichever of those it also closed.
--
-- Linear and last-touch totals both add back to the same amount of money,
-- because BQ03B handed out each surviving purchase once under each model.
-- What changes between the two columns is which channel is holding it, which
-- is the gap a budget decision reads.
--
-- The output holds one row per channel. This is the final table.
-- ------------------------------------------------------------
channel_attribution_credit_aggregated_metrics AS
(
    SELECT
        TOUCHPOINT_CHANNEL_GROUPING
            AS CHANNEL_GROUPING,

        SUM(LINEAR_CREDIT_TRANSACTIONS)
            AS LINEAR_CREDIT_TRANSACTIONS,

        SUM(LINEAR_CREDIT_REVENUE)
            AS LINEAR_CREDIT_REVENUE,

        SUM(LAST_TOUCH_CREDIT_TRANSACTIONS)
            AS LAST_TOUCH_CREDIT_TRANSACTIONS,

        SUM(LAST_TOUCH_CREDIT_REVENUE)
            AS LAST_TOUCH_CREDIT_REVENUE

    FROM purchase_touchpoint_credit_filtered
    GROUP BY TOUCHPOINT_CHANNEL_GROUPING
)
SELECT *
FROM channel_attribution_credit_aggregated_metrics;