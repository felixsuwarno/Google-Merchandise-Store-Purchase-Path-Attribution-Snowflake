USE DATABASE DASHVIO;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ03  (Table 2 of 3: BQ03B_PATH_CREDIT_ASSIGNED)
--
-- Business question:
-- "Under last-touch and linear attribution, how much transaction and
--  revenue credit does each channel receive?"
--
-- BQ03A built a path for every purchase. This table does two things:
-- it removes the paths the comparison cannot use, then assigns credit to the
-- sessions in the paths that remain.
--
-- Why some paths are removed:
-- A path that touched only one distinct channel gives last-touch and linear
-- the same channel-level answer, always. Last-touch hands the purchase to the
-- closing session's channel. Linear splits the purchase across the path's
-- sessions, but every session is that same channel, so the split lands back on
-- it. Both models return 100% to the one channel. This holds no matter how
-- many sessions the path has: a single-session purchase and a four-session
-- all-Referral purchase both collapse to the same number under both models.
--
-- Adobe's attribution documentation states the single-touchpoint case directly
-- (a one-touchpoint conversion gives that touchpoint 100% under any rule). The
-- extension to same-channel multi-session paths follows from the same
-- arithmetic and was verified on this project's data, not taken from a source.
--
-- How this differs from GA4 and Adobe CJA:
-- Both platforms keep single-channel and single-touchpoint paths in their
-- totals; they never split them out. This project removes them on purpose,
-- because the business question drives a budget-reallocation decision, and a
-- path where the two models cannot disagree carries no signal for moving
-- budget between channels. Removing them is a deliberate departure from
-- default tooling, not standard practice.
--
-- Two attribution models are calculated on every surviving session:
-- if linear     : every session in the path gets an equal share of the purchase
-- if last-touch : the closing session takes the whole purchase, the rest get 0
--
-- Both are calculated on the same row so BQ03C can compare them by channel.
--
-- Output: one row per visitor + purchase session + path session, for paths
-- with more than one distinct channel, carrying four credit amounts and the
-- channel that earned them.
--
-- Definitions:
--   - The paths come from BQ03A. This table does not rebuild them.
--   - The purchase session is inside its own path, so last-touch always has
--     exactly one session to land on.
--   - Single-channel paths (which include every single-session purchase) are
--     dropped in Step 2, before any credit is calculated, because the two
--     models are forced to agree on them.
--   - Credit is assigned only across sessions and purchases observed between
--     2016-08-01 and 2017-08-01.
-- ============================================================


--CREATE OR REPLACE TABLE --DASHVIO.ANALYTICS.BQ03B_PATH_CREDIT_ASSIGNED AS


-- ------------------------------------------------------------
-- Step 1 - Measure how long each path is and how many channels it holds
-- CTE name: purchase_paths_aggregated_metrics
--
-- Before a single-channel path can be dropped, the path has to be counted.
-- Neither the length of a path nor the number of channels in it is knowable
-- from a single session row; both only exist once every session belonging to
-- the path has been assembled, which is what BQ03A_PURCHASE_PATHS holds.
--
-- Rows are grouped by VISITOR_ID and PURCHASE_SESSION_ID, which together
-- identify one path.
--
-- PATH_TOUCHPOINT_COUNT:
-- How many sessions the path holds. This is the divisor for linear credit,
-- calculated later in Step 4.
--
-- PATH_DISTINCT_CHANNEL_COUNT:
-- How many different values of TOUCHPOINT_CHANNEL_GROUPING appear in the path.
-- A path that touched Referral three times and Direct once holds two
-- channels, not four. Step 2 uses this count to decide which paths continue.
--
-- The output holds one row per path. Once this is done, the next CTE can
-- remove the paths that hold only one channel.
-- ------------------------------------------------------------
WITH purchase_paths_aggregated_metrics AS
(
    SELECT
        VISITOR_ID,
        PURCHASE_SESSION_ID,

        COUNT(*)                                        AS PATH_TOUCHPOINT_COUNT,
        COUNT(DISTINCT TOUCHPOINT_CHANNEL_GROUPING)     AS PATH_DISTINCT_CHANNEL_COUNT

    FROM DASHVIO.ANALYTICS.BQ03A_PURCHASE_PATHS
    GROUP BY
        VISITOR_ID,
        PURCHASE_SESSION_ID
),


-- ------------------------------------------------------------
-- Step 2 - Keep only the paths where the two models can disagree
-- CTE name: purchase_paths_multi_channel_filtered
--
-- A single-channel path gives last-touch and linear the same channel-level
-- answer no matter how many sessions it holds: three Referral sessions split
-- three ways still leave Referral with the whole purchase. That path cannot
-- tell a budget decision anything a simpler total-revenue number would not
-- already show, so it is removed here, before any session-level credit is
-- calculated on it.
--
-- PATH_DISTINCT_CHANNEL_COUNT lives in purchase_paths_aggregated_metrics from
-- Step 1. This CTE keeps path rows where PATH_DISTINCT_CHANNEL_COUNT is
-- greater than 1 and removes every path with only one distinct channel,
-- including every single-session purchase, since a single session can only
-- ever hold one channel.
--
-- The output holds one row per surviving path. Once this is done, the next
-- CTE only has to join the touchpoints of paths that made it through this
-- filter, instead of every path BQ03A built.
-- ------------------------------------------------------------
purchase_paths_multi_channel_filtered AS
(
    SELECT
        VISITOR_ID,
        PURCHASE_SESSION_ID,
        PATH_TOUCHPOINT_COUNT
    FROM purchase_paths_aggregated_metrics
    WHERE PATH_DISTINCT_CHANNEL_COUNT > 1
),


-- ------------------------------------------------------------
-- Step 3 - Attach the path length to each surviving touchpoint
-- CTE name: purchase_touchpoints_path_metrics_join
--
-- Credit is calculated one session at a time, and that calculation needs
-- PATH_TOUCHPOINT_COUNT, a number that only exists at path level. A session
-- cannot see how long its own path is on its own.
--
-- The session rows live in BQ03A_PURCHASE_PATHS, and the surviving paths with
-- their length live in purchase_paths_multi_channel_filtered from Step 2. This
-- CTE joins them on VISITOR_ID and PURCHASE_SESSION_ID, the pair that
-- identifies a path.
--
-- Because Step 2 already dropped single-channel paths, a touchpoint whose
-- path was removed finds no match here and is dropped along with it. This is
-- where the single-channel session rows actually leave the pipeline; nothing
-- downstream of this step ever sees them.
--
-- It carries the two anchor measures, the two session identities, and the
-- touchpoint channel, because Step 4 needs the anchor measures to know how
-- much money there is and the two session identities to recognise which row
-- closed the purchase.
--
-- Once this is done, every surviving row holds everything the credit
-- calculation needs.
-- ------------------------------------------------------------
purchase_touchpoints_path_metrics_join AS
(
    SELECT
        pp.VISITOR_ID,
        pp.PURCHASE_SESSION_ID,
        pp.ANCHOR_TRANSACTION_COUNT,
        pp.ANCHOR_TRANSACTION_REVENUE,
        pp.TOUCHPOINT_SESSION_ID,
        pp.TOUCHPOINT_CHANNEL_GROUPING,
        pm.PATH_TOUCHPOINT_COUNT

    FROM DASHVIO.ANALYTICS.BQ03A_PURCHASE_PATHS pp
    INNER JOIN purchase_paths_multi_channel_filtered pm
        ON pp.VISITOR_ID = pm.VISITOR_ID
       AND pp.PURCHASE_SESSION_ID = pm.PURCHASE_SESSION_ID
),


-- ------------------------------------------------------------
-- Step 4 - Hand out the purchase under both attribution models
-- CTE name: purchase_touchpoints_attribution_credit_calculated
--
-- The business question compares two ways of crediting the same purchase, so
-- both answers are calculated on the same row. The money lives in
-- purchase_touchpoints_path_metrics_join in ANCHOR_TRANSACTION_COUNT and
-- ANCHOR_TRANSACTION_REVENUE, the divisor lives in PATH_TOUCHPOINT_COUNT, and
-- the identity of the closing session is settled by comparing
-- TOUCHPOINT_SESSION_ID against PURCHASE_SESSION_ID.
--
-- LINEAR_CREDIT_TRANSACTIONS:
-- ANCHOR_TRANSACTION_COUNT divided by PATH_TOUCHPOINT_COUNT.
--
-- LINEAR_CREDIT_REVENUE:
-- ANCHOR_TRANSACTION_REVENUE divided by PATH_TOUCHPOINT_COUNT.
--
-- Both are multiplied by 1.000000000000 first so the division keeps its
-- decimals instead of being cut back to a whole number.
--
-- LAST_TOUCH_CREDIT_TRANSACTIONS:
--   if TOUCHPOINT_SESSION_ID = PURCHASE_SESSION_ID : ANCHOR_TRANSACTION_COUNT
--   if it does not match                           : 0
--
-- LAST_TOUCH_CREDIT_REVENUE:
--   if TOUCHPOINT_SESSION_ID = PURCHASE_SESSION_ID : ANCHOR_TRANSACTION_REVENUE
--   if it does not match                           : 0
--
-- Exactly one session in each path matches, so each purchase is handed out
-- once under last-touch and once under linear. Both models total back to the
-- same amount of money within this table, which is what makes them
-- comparable in BQ03C. That total is smaller than all observed revenue, since
-- Step 2 already removed every single-channel path.
--
-- Linear pays every session in the path, and for a repeat buyer one of those
-- sessions can be the previous purchase. That session already took
-- last-touch credit for its own purchase and now takes a linear share of the
-- next one. The path rule in BQ03A puts it there on purpose, but it means
-- linear credit for a closing-heavy channel carries some of its own earlier
-- revenue.
--
-- No rows are removed. The anchor measures and PATH_TOUCHPOINT_COUNT are
-- dropped now that they have been spent. What stays is the two session
-- identities, the channel that earned the credit, and the four credit
-- amounts, which is everything BQ03C needs to total by channel.
-- ------------------------------------------------------------
purchase_touchpoints_attribution_credit_calculated AS
(
    SELECT
        VISITOR_ID,
        PURCHASE_SESSION_ID,
        TOUCHPOINT_SESSION_ID,
        TOUCHPOINT_CHANNEL_GROUPING,

        (ANCHOR_TRANSACTION_COUNT * 1.000000000000)
            / PATH_TOUCHPOINT_COUNT
            AS LINEAR_CREDIT_TRANSACTIONS,

        (ANCHOR_TRANSACTION_REVENUE * 1.000000000000)
            / PATH_TOUCHPOINT_COUNT
            AS LINEAR_CREDIT_REVENUE,

        CASE
            WHEN TOUCHPOINT_SESSION_ID = PURCHASE_SESSION_ID
                THEN ANCHOR_TRANSACTION_COUNT
            ELSE 0
        END AS LAST_TOUCH_CREDIT_TRANSACTIONS,

        CASE
            WHEN TOUCHPOINT_SESSION_ID = PURCHASE_SESSION_ID
                THEN ANCHOR_TRANSACTION_REVENUE
            ELSE 0
        END AS LAST_TOUCH_CREDIT_REVENUE

    FROM purchase_touchpoints_path_metrics_join
)
SELECT *
FROM purchase_touchpoints_attribution_credit_calculated;