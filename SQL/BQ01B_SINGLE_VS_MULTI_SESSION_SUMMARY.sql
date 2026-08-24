USE DATABASE DASHVIO;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ01B_SINGLE_VS_MULTI_SESSION_SUMMARY
-- ============================================================

-- CREATE OR REPLACE TABLE BQ01B_SINGLE_VS_MULTI_SESSION_SUMMARY AS

-- BQ01_SINGLE_VS_MULTI_SESSION_SUMMARY
-- Business question:
-- What share of purchasing visitors made their purchase in their first session (single-session) 
-- versus after multiple sessions (multi-session)?

-- ------------------------------------------------------------
-- Step 1 - Summarize the share of single vs multi-session visitors
-- CTE name: session_count_group_aggregated_metrics
--
-- BQ01A_VISITOR_SESSION_COUNT_LABELED already categorized visitors
-- into:
-- single-session group
-- multi-session group
--
-- This step counts visitors in each group, then divides each count
-- by the total visitor count to calculate VISITOR_SHARE.
-- ------------------------------------------------------------

WITH session_count_group_aggregated_metrics AS 
(
    SELECT
        SESSION_COUNT_GROUP,

        COUNT(DISTINCT VISITOR_ID) AS REVENUE_SESSION_VISITORS,

        (
            COUNT(DISTINCT VISITOR_ID)::FLOAT
            /
            SUM(COUNT(DISTINCT VISITOR_ID)) OVER () 
        ) AS VISITOR_SHARE

    FROM DASHVIO.ANALYTICS.BQ01A_VISITOR_SESSION_COUNT_LABELED
    GROUP BY SESSION_COUNT_GROUP
)

SELECT *
FROM session_count_group_aggregated_metrics;