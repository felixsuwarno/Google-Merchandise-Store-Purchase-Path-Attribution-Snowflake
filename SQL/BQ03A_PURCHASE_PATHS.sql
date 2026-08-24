USE DATABASE DASHVIO;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ03  (Table 1 of 3: BQ03A_PURCHASE_PATHS)
--
-- Business question:
-- "Under last-touch and linear attribution, how much transaction and
--  revenue credit does each channel receive?"
--
-- This is the first of three tables that answer that question.
-- BQ03A assembles the paths. BQ03B assigns credit. BQ03C totals by channel.
-- BQ03A does not answer the business question on its own; it prepares the
-- input the other two need.
--
-- What BQ03A does:
-- For every purchase a visitor made, it collects the sessions that belong to
-- that purchase's path:
-- if     earliest observed purchase : the sessions from the start of the
--                                     visitor's observed history up to that purchase
-- if not earliest observed purchase : the sessions from the visitor's previous
--                                     purchase up to that purchase
--
-- How this compares to GA4 and Adobe CJA:
-- GA4 and Adobe both attribute against a conversion path and let the platform
-- bound it with a lookback window. This project bounds each path by the
-- visitor's previous purchase instead, because the business question is about
-- credit between consecutive purchases, not credit inside a fixed day window.
-- BQ04 will test a fixed-window bound separately. Note also that GA4 retired
-- linear attribution from its interface in November 2023, keeping only
-- last-click and its machine-learning data-driven model, so this last-touch
-- versus linear comparison is a computation GA4 no longer offers directly.
--
-- Output: one row per visitor + purchase session + path session.
--
-- Definitions:
--   - Purchase = a revenue session (IS_REVENUE_SESSION = TRUE).
--   - The purchase session sits inside its own path. It is the closing
--     touchpoint, and it is the row BQ03B credits under last-touch.
--   - The previous purchase session also sits inside the next path. Paths meet
--     at their shared boundary. This is the same interpurchase rule BQ02B uses.
--   - That shared boundary means a repeat buyer's purchase session appears in
--     two paths: as the closing touchpoint of its own purchase, and as the
--     opening touchpoint of the next one. Under linear attribution it is paid
--     twice, so a channel that closes purchases also collects assist credit
--     for having closed them. Read linear credit for a closing-heavy channel
--     with that in mind: part of the gap between its linear and last-touch
--     totals is the window rule, not browsing behaviour.
--   - No path filtering happens here. Whether a path is single-channel or
--     multi-channel cannot be known until every session in it has been
--     assembled, which is a fact BQ03B computes. BQ03A therefore builds a path
--     for every purchase, and BQ03B drops the ones the comparison cannot use.
--   - Sessions observed between 2016-08-01 and 2017-08-01 only. A visitor's
--     earliest session here is not their earliest session ever, so the path
--     opening a visitor's earliest observed purchase is bounded by the
--     dataset, not by the visitor's real history.
-- ============================================================


-- CREATE OR REPLACE TABLE DASHVIO.ANALYTICS.BQ03A_PURCHASE_PATHS AS


-- ------------------------------------------------------------
-- Step 1 - Pull the session fields and name the missing channels
-- CTE name: sessions_channel_grouping_labeled
--
-- Pull necessary data from STG_SESSION
-- these are all sessions available

-- ------------------------------------------------------------
WITH sessions_channel_grouping_labeled AS
(
    SELECT
        VISITOR_ID,
        SESSION_ID,
        VISIT_START_TIMESTAMP AS TOUCHPOINT_TIMESTAMP,
        IS_REVENUE_SESSION,

        COALESCE(TRANSACTION_COUNT  , 0        )   AS TRANSACTION_COUNT,
        COALESCE(TRANSACTION_REVENUE, 0        )   AS TRANSACTION_REVENUE,
        COALESCE(CHANNEL_GROUPING   , 'UNKNOWN')   AS CHANNEL_GROUPING_LABELED

    FROM DASHVIO.STAGING.STG_SESSIONS
),


-- ------------------------------------------------------------
-- Step 2 - Put each visitor's purchases in the order they happened
-- CTE name: purchase_anchors_sequenced
--
-- Each purchase anchors one path, and each path is bounded by the purchase
-- before it. Before any boundary can be worked out, the purchases have to be
-- lined up in time order.
-- 
-- So basically this CTE gets all session / rows where a purchase happens
-- (IS_REVENUE_SESSION = TRUE)
-- 
-- Then for each visitor, it ranks the timestamp sequence by using row_number()
-- The purpose of it is so that it can later be used to flag the previous purchase session
-- as a starting window for each purchase


-- ------------------------------------------------------------
purchase_anchors_sequenced AS
(
    SELECT
        VISITOR_ID,
        SESSION_ID                  AS PURCHASE_SESSION_ID,
        TOUCHPOINT_TIMESTAMP        AS PURCHASE_SESSION_TIMESTAMP,
        CHANNEL_GROUPING_LABELED    AS CLOSING_CHANNEL_GROUPING,
        TRANSACTION_COUNT           AS ANCHOR_TRANSACTION_COUNT,
        TRANSACTION_REVENUE         AS ANCHOR_TRANSACTION_REVENUE,

        ROW_NUMBER() OVER
        (
            PARTITION BY VISITOR_ID
            ORDER BY TOUCHPOINT_TIMESTAMP
        ) AS PURCHASE_SEQUENCE

    FROM sessions_channel_grouping_labeled
    WHERE IS_REVENUE_SESSION = TRUE
),


-- ------------------------------------------------------------
-- Step 3 - Give each purchase its window start
-- CTE name: purchase_anchors_window_start_calculated
--
-- The window is simply the visitor's purchase rows, lagged by one.
--
-- WINDOW_START_TIMESTAMP:
-- LAG pulls the visitor's immediately previous purchase timestamp, ordered by
-- PURCHASE_SEQUENCE. This is the inclusive lower bound of the path window in
-- Step 4. The earliest purchase has no previous purchase, so it gets NULL, and
-- Step 4 treats NULL as no lower bound.

-- ------------------------------------------------------------
purchase_anchors_window_start_calculated AS
(
    SELECT
        VISITOR_ID,
        PURCHASE_SESSION_ID,
        PURCHASE_SESSION_TIMESTAMP,
        CLOSING_CHANNEL_GROUPING,
        ANCHOR_TRANSACTION_COUNT,
        ANCHOR_TRANSACTION_REVENUE,
        PURCHASE_SEQUENCE,

        LAG(PURCHASE_SESSION_TIMESTAMP) OVER
        (
            PARTITION BY VISITOR_ID
            ORDER BY PURCHASE_SEQUENCE
        ) AS WINDOW_START_TIMESTAMP

    FROM purchase_anchors_sequenced
),


-- ------------------------------------------------------------
-- Step 4 - Pair every purchase with that visitor's sessions
-- CTE name: purchase_anchors_sessions_join
--
-- The answer this table owes BQ03B is the list of sessions belonging to each
-- purchase. The purchases and their lower bound live in
-- purchase_anchors_window_start_calculated. The sessions themselves live back
-- in sessions_channel_grouping_labeled, which is why that CTE is joined in
-- here rather than being read again from staging.
--
-- The two are matched on VISITOR_ID only. Each purchase is paired with every
-- session belonging to that visitor. No window filtering happens yet; Step 5
-- trims each pair to the purchase's window.
--
-- TOUCHPOINT_TIMESTAMP already carries its final name from Step 1, so no
-- rename is needed here. The purchase side keeps PURCHASE_SESSION_TIMESTAMP
-- and WINDOW_START_TIMESTAMP because Step 5 needs both bounds to filter.
-- ------------------------------------------------------------
purchase_anchors_sessions_join AS
(
    SELECT
        wb.PURCHASE_SESSION_ID,
        s.SESSION_ID                    AS TOUCHPOINT_SESSION_ID,

        wb.VISITOR_ID,
        wb.PURCHASE_SESSION_TIMESTAMP,
        wb.WINDOW_START_TIMESTAMP,
        wb.CLOSING_CHANNEL_GROUPING,
        wb.ANCHOR_TRANSACTION_COUNT,
        wb.ANCHOR_TRANSACTION_REVENUE,
        wb.PURCHASE_SEQUENCE,

        s.TOUCHPOINT_TIMESTAMP,
        s.CHANNEL_GROUPING_LABELED      AS TOUCHPOINT_CHANNEL_GROUPING

    FROM purchase_anchors_window_start_calculated wb
    INNER JOIN sessions_channel_grouping_labeled s
        ON s.VISITOR_ID = wb.VISITOR_ID
),


-- ------------------------------------------------------------
-- Step 5 - Keep the sessions inside each purchase's window
-- CTE name: purchase_anchors_sessions_windowed
--
-- Step 4 paired each purchase with all of the visitor's sessions. This CTE
-- trims each pair to the sessions that actually belong to the purchase's path.
--
--   upper bound
--   TOUCHPOINT_TIMESTAMP <= PURCHASE_SESSION_TIMESTAMP
--   the session happened at or before the purchase being processed.
--   The bound is inclusive, so the purchase session matches its own path.
--   That row is the one BQ03B credits under last-touch, and without it
--   last-touch would have nothing to land on.
--
--   lower bound
--   WINDOW_START_TIMESTAMP IS NULL OR TOUCHPOINT_TIMESTAMP >= WINDOW_START_TIMESTAMP
--   for a repeat purchase, keep sessions at or after the previous purchase.
--   For the earliest purchase, WINDOW_START_TIMESTAMP is NULL, so no lower
--   bound is applied and the path opens at the start of observed history.
--
-- A session outside those bounds is removed from that path. The same session
-- can still remain in a different purchase of the same visitor.
--
-- WINDOW_START_TIMESTAMP has done its job and is dropped. PURCHASE_SESSION_TIMESTAMP,
-- TOUCHPOINT_TIMESTAMP, and PURCHASE_SEQUENCE are kept for audit so one
-- visitor's paths can be read in order and inspected row by row. Once this is
-- done, BQ03B has the paths it needs.
-- ------------------------------------------------------------
purchase_anchors_sessions_windowed AS
(
    SELECT
        PURCHASE_SESSION_ID,
        TOUCHPOINT_SESSION_ID,

        VISITOR_ID,
        PURCHASE_SESSION_TIMESTAMP,
        CLOSING_CHANNEL_GROUPING,
        ANCHOR_TRANSACTION_COUNT,
        ANCHOR_TRANSACTION_REVENUE,
        PURCHASE_SEQUENCE,
        TOUCHPOINT_TIMESTAMP,
        TOUCHPOINT_CHANNEL_GROUPING
    FROM purchase_anchors_sessions_join
    WHERE
        TOUCHPOINT_TIMESTAMP <= PURCHASE_SESSION_TIMESTAMP
        AND
        (
            WINDOW_START_TIMESTAMP  IS NULL
            OR 
            TOUCHPOINT_TIMESTAMP    >= WINDOW_START_TIMESTAMP
        )
)
SELECT *
FROM purchase_anchors_sessions_windowed;