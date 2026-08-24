USE DATABASE DASHVIO;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ02A_MULTI_SESSION_CONVERTING_CHANNEL
-- Business question:
-- For multi-session visitors, what channel did they convert on?
--
-- BQ01A_VISITOR_SESSION_COUNT_LABELED contains only:
-- VISITOR_ID and SESSION_COUNT_GROUP.
--
-- The revenue-session timestamp and channel must therefore come
-- from STG_SESSIONS.
-- ============================================================

-- CREATE OR REPLACE TABLE DASHVIO.ANALYTICS.BQ02A_MULTI_SESSION_CONVERTING_CHANNEL AS


-- ------------------------------------------------------------
-- Step 1 - Keep visitors labeled as multi-session
-- CTE name: visitors_multi_session_filtered
--
-- BQ01A already categorized each visitor as SINGLE_SESSION or
-- MULTI_SESSION.
--
-- This CTE keeps visitors labeled MULTI_SESSION and removes
-- visitors labeled SINGLE_SESSION. 

-- It keeps only VISITOR_ID because that is the only field needed 
-- to match these visitors to their revenue sessions.
-- ------------------------------------------------------------

WITH visitors_multi_session_filtered AS
(
    SELECT
        VISITOR_ID

    FROM DASHVIO.ANALYTICS.BQ01A_VISITOR_SESSION_COUNT_LABELED

    WHERE SESSION_COUNT_GROUP = 'MULTI_SESSION'
),


-- ------------------------------------------------------------
-- Step 2 - Keep session channel fields
-- CTE name: sessions_channel_fields_filtered
--
-- BQ01A already identified the visitors who made a purchase after
-- multiple observed sessions. 

-- Now we go back to STG_SESSIONS to fetch all sessions where 
-- transaction happens by filtering the rows using IS_REVENUE_SESSION = TRUE

-- We need the Channel_Grouping : this is the column that explains
-- what channel the visitor use to come when he makes a transaction.

-- we do this because we will join this with the previous step

-- ------------------------------------------------------------

sessions_revenue_channel_filtered AS
(
    SELECT
        VISITOR_ID,
        VISIT_START_TIMESTAMP,
        CHANNEL_GROUPING

    FROM DASHVIO.STAGING.STG_SESSIONS

    WHERE IS_REVENUE_SESSION = TRUE
),


-- ------------------------------------------------------------
-- Step 3 - Join multi-session visitors to their revenue sessions
-- CTE name: visitors_multi_session_sessions_revenue_join
--
-- This CTE joins visitors_multi_session_filtered to
-- sessions_revenue_channel_filtered using VISITOR_ID.
--
-- Goal : need to fetch Channel Grouping : this stores channel name
-- the visitor used to make the visit.
--
-- ------------------------------------------------------------

visitors_multi_session_sessions_revenue_join AS
(
    SELECT
        v.VISITOR_ID,
        s.CHANNEL_GROUPING

    FROM visitors_multi_session_filtered AS v

    INNER JOIN sessions_revenue_channel_filtered AS s
        ON v.VISITOR_ID = s.VISITOR_ID
),


-- ------------------------------------------------------------
-- Step 4 - Summarize converting revenue sessions by channel
-- CTE name: visitors_converting_channel_aggregated_metrics

-- This CTE will make a descriptive information about 
-- channels visitors use when they make a purchase.

-- It groups Channel Grouping and shows :
-- 1- how many revenue sessions occurred through each channel
-- 2- calculates each channel's share of all matching revenue sessions.

-- NULL channels are reported as UNKNOWN. The channels are sorted
-- from the highest revenue-session count to the lowest, so the
-- first row shows the channel that appears most often.
-- ------------------------------------------------------------

visitors_converting_channel_aggregated_metrics AS
(
    SELECT
        COALESCE(CHANNEL_GROUPING, 'UNKNOWN') AS CONVERTING_CHANNEL,

        COUNT(*) AS CONVERTING_REVENUE_SESSION_COUNT,

        COUNT(*)::FLOAT
        /
        SUM(COUNT(*)) OVER () AS CONVERTING_REVENUE_SESSION_SHARE

    FROM visitors_multi_session_sessions_revenue_join

    GROUP BY COALESCE(CHANNEL_GROUPING, 'UNKNOWN')

    ORDER BY
        CONVERTING_REVENUE_SESSION_COUNT DESC,
        CONVERTING_CHANNEL
)

SELECT *
FROM visitors_converting_channel_aggregated_metrics;