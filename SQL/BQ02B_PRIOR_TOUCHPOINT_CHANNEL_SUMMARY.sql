USE DATABASE DASHVIO;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ02B_PRIOR_TOUCHPOINT_CHANNEL_SUMMARY
-- "Which channels do multi-session visitors use before they purchase, and which ones are used most?"

-- For each purchase made by a multi-session visitor, we look back at the
-- sessions that came before it:
-- if     first purchase : the sessions from the start of their observed history
-- if not first purchase : the sessions since their last purchase

-- Then we count those sessions by channel, so the answer is a ranked
-- channel list a reader can act on, not one line per visitor.


-- Output: one row per browse channel,
-- showing how many purchase paths it reached and how many touches it made.
--
-- Definitions:
--   - Purchase = a revenue session (IS_REVENUE_SESSION = TRUE).
--   - A prior purchase is NOT counted here. It is not a marketing channel,
--     and this table is built to compare against BQ02A's closing channels.
--   - Touchpoints are windowed between consecutive purchases, so a
--     browse is never counted against two purchases.


-- CREATE OR REPLACE TABLE DASHVIO.ANALYTICS.BQ02B_PRIOR_TOUCHPOINT_CHANNEL_SUMMARY AS

-- ------------------------------------------------------------
-- Step 1 - Keep the multi-session visitors
-- CTE name: visitors_multi_session_filtered
--
-- BQ01A already categorized each visitor as SINGLE_SESSION or
-- MULTI_SESSION. This CTE keeps visitors labeled MULTI_SESSION and
-- removes visitors labeled SINGLE_SESSION. It keeps VISITOR_ID
-- because that is the only field needed to match these visitors to
-- their sessions.
-- ------------------------------------------------------------
WITH visitors_multi_session_filtered AS
(
    SELECT
        VISITOR_ID
    FROM DASHVIO.ANALYTICS.BQ01A_VISITOR_SESSION_COUNT_LABELED
    WHERE SESSION_COUNT_GROUP = 'MULTI_SESSION'
),



-- ------------------------------------------------------------
-- Step 2 - Keep the revenue sessions
-- CTE name: sessions_purchase_filtered
--

-- We know who the multisession visitors who make purchases from cte1.
-- Now we need to retrieve their session data.

-- That means we need to join table from cte1 with STG_SESSIONS,
-- but STG_SESSIONS need to be filtered first before the join:

-- At STG_SESSIONS, we find rows of data ( sessions data ) that is marked
-- IS_REVENUE_SESSION = TRUE.

-- ------------------------------------------------------------
sessions_purchase_filtered AS
(
    SELECT
        VISITOR_ID,
        VISIT_START_TIMESTAMP
    FROM DASHVIO.STAGING.STG_SESSIONS
    WHERE IS_REVENUE_SESSION = TRUE
),


-- ------------------------------------------------------------
-- Step 3 - Keep the purchases belonging to multi-session visitors
-- CTE name: visitors_multi_session_purchases_join
--
-- Join the two prior CTEs on VISITOR_ID: keep purchase timestamps
-- for multi-session visitors, drop everyone else. Feeds the window
-- in Step 4.
-- ------------------------------------------------------------

visitors_multi_session_purchases_join AS
(
    SELECT
        p.VISITOR_ID,
        p.VISIT_START_TIMESTAMP AS PURCHASE_SESSION_TS
    FROM sessions_purchase_filtered AS p
    INNER JOIN visitors_multi_session_filtered AS v
        ON p.VISITOR_ID = v.VISITOR_ID
),


-- ------------------------------------------------------------
-- Step 4 - Give each purchase its window start
-- CTE name: visitors_purchase_window_start_calculated
--
-- The column comes from ordering each visitor's purchases by time
-- (PARTITION BY VISITOR_ID ORDER BY PURCHASE_SESSION_TS).
--
-- PREV_PURCHASE_TS:
-- LAG pulls the visitor's immediately previous purchase timestamp.
-- This is the inclusive lower bound of the touchpoint window in Step 7.
-- The first purchase has no previous purchase, so it gets NULL.
--
-- No rows are removed here, so this CTE also holds the complete list
-- of purchase paths. Step 8 counts it for the PATH_SHARE denominator.
-- ------------------------------------------------------------

visitors_purchase_window_start_calculated AS
(
    SELECT
        VISITOR_ID,
        PURCHASE_SESSION_TS,

        LAG(PURCHASE_SESSION_TS) OVER
        (
            PARTITION BY VISITOR_ID
            ORDER BY PURCHASE_SESSION_TS
        ) AS PREV_PURCHASE_TS
    FROM visitors_multi_session_purchases_join
),


-- ------------------------------------------------------------
-- Step 5 - Label every session as a browse channel or a purchase
-- CTE name: sessions_touchpoint_category_labeled
--
-- This starts a separate branch.
-- Steps 2-4 built the purchase anchors;
-- this CTE goes back to STG_SESSIONS to prepare the
-- touchpoint side for the join in Step 6 by creating one
-- flag / filtering column.

-- TOUCHPOINT_CATEGORY:
--   if IS_REVENUE_SESSION is TRUE  : 'PURCHASE'
--   if IS_REVENUE_SESSION is FALSE : CHANNEL_GROUPING
--                                    (if CHANNEL_GROUPING is NULL : 'UNKNOWN')
-- So a purchase and a browse sit in one column, distinguishable.
-- Step 7 uses that to drop the purchases and keep the browse channels.

-- ------------------------------------------------------------

sessions_touchpoint_category_labeled AS
(
    SELECT
        VISITOR_ID,
        VISIT_START_TIMESTAMP AS TOUCHPOINT_TS,

        CASE
            WHEN IS_REVENUE_SESSION = TRUE THEN 'PURCHASE'
            ELSE COALESCE(CHANNEL_GROUPING, 'UNKNOWN')
        END AS TOUCHPOINT_CATEGORY
        
    FROM DASHVIO.STAGING.STG_SESSIONS
),


-- ------------------------------------------------------------
-- Step 6 - Pair every purchase with that visitor's sessions
-- CTE name: visitors_purchase_touchpoints_join
--
-- Join the purchase anchors from Step 4 to the labeled sessions
-- from Step 5 using VISITOR_ID.
--
-- Each purchase is paired with all sessions belonging to that
-- visitor. No timestamp filtering happens yet.
--
-- Keep:
--   PURCHASE_SESSION_TS         : current purchase timestamp
--   PREV_PURCHASE_TS            : previous purchase timestamp
--   TOUCHPOINT_TS               : session timestamp
--   TOUCHPOINT_CATEGORY         : PURCHASE or browse channel
--
-- Step 7 needs these columns to keep only the sessions belonging
-- to each purchase window.
-- ------------------------------------------------------------
visitors_purchase_touchpoints_join AS
(
    SELECT
        p.VISITOR_ID,
        p.PURCHASE_SESSION_TS,
        p.PREV_PURCHASE_TS,
        t.TOUCHPOINT_TS,
        t.TOUCHPOINT_CATEGORY
    FROM visitors_purchase_window_start_calculated AS p
    INNER JOIN sessions_touchpoint_category_labeled AS t
        ON p.VISITOR_ID = t.VISITOR_ID
),


-- ------------------------------------------------------------
-- Step 7 - Keep prior browse sessions inside each purchase window
-- CTE name: visitors_purchase_touchpoints_windowed
--
-- The upper bound is the current purchase timestamp:
--
-- TOUCHPOINT_TS < PURCHASE_SESSION_TS
--
-- This keeps sessions that happened before the current purchase.
-- The current purchase session itself is excluded.
--
-- The lower bound is the previous purchase timestamp:
--
-- TOUCHPOINT_TS >= PREV_PURCHASE_TS
--
-- This keeps sessions that happened at or after the previous
-- purchase. If PREV_PURCHASE_TS is NULL, the current purchase is
-- the visitor's first purchase, so no lower bound is applied.
--
-- Revenue sessions are labeled PURCHASE in Step 5. Those rows are
-- removed because this table counts only prior browse channels.
--
-- Each remaining row represents one eligible prior browse session
-- belonging to one purchase path.
-- ------------------------------------------------------------
visitors_purchase_touchpoints_windowed AS
(
    SELECT
        VISITOR_ID,
        PURCHASE_SESSION_TS,
        TOUCHPOINT_CATEGORY
    FROM visitors_purchase_touchpoints_join
    WHERE TOUCHPOINT_TS < PURCHASE_SESSION_TS
        AND
        (
            PREV_PURCHASE_TS IS NULL
            OR TOUCHPOINT_TS >= PREV_PURCHASE_TS
        )
        AND TOUCHPOINT_CATEGORY <> 'PURCHASE'
),


-- ------------------------------------------------------------
-- Step 8 - Count the prior browse channels
-- CTE name: prior_touchpoint_channel_aggregated_metrics
--
-- Group the visits from Step 7 by TOUCHPOINT_CATEGORY.
--
-- After Step 7 removes PURCHASE, every remaining
-- TOUCHPOINT_CATEGORY is a browse channel.
--
-- TOUCHPOINT_COUNT:
-- Count every visit made through this channel before a purchase.
-- If one purchase had three Referral visits before it, all three
-- are counted.
--
-- TOUCHPOINT_SHARE:
-- Divide this channel's visits by all visits made before purchases.
-- Every visit belongs to exactly one channel, so the shares sum to 1.
-- ------------------------------------------------------------
prior_touchpoint_channel_aggregated_metrics AS
(
    SELECT
        TOUCHPOINT_CATEGORY,

        COUNT(*) AS TOUCHPOINT_COUNT,

        CAST(COUNT(*) AS NUMBER(38,15))
        /
        (
            SELECT COUNT(*)
            FROM visitors_purchase_touchpoints_windowed
        ) AS TOUCHPOINT_SHARE

    FROM visitors_purchase_touchpoints_windowed
    GROUP BY TOUCHPOINT_CATEGORY
    ORDER BY TOUCHPOINT_COUNT DESC
)

SELECT *
FROM prior_touchpoint_channel_aggregated_metrics;