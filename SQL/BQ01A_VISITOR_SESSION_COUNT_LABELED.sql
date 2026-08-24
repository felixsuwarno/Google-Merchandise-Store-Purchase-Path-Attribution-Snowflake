USE DATABASE DASHVIO;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ01A_VISITOR_SESSION_COUNT_LABELED
--
-- This physical table is shared by BQ01B, BQ02A, and BQ02C.
-- It contains one row per visitor with an observed purchase.
-- ============================================================


-- ============================================================
-- BQ01_SINGLE_VS_MULTI_SESSION_SUMMARY
-- Business question:
-- What What share of purchasing visitors made their purchase in their first session (single-session) 
-- versus after multiple sessions (multi-session)?
--
-- We compare :
-- GROUP 1 : visitors who made a purchase in their first observed session in the dataset
-- versus 
-- GROUP 2 : visitors who had multiple observed sessions before making a purchase.
--
-- That means we only consider all visitors who make a purchase.
-- Those who dont make any transaction are excluded from calculation.
--
-- Additional note :
-- This dataset covers only a limited time window. We cannot know when
-- a visitor first visited the website ever. Their first observed visit
-- is only their earliest visit recorded within this dataset.

-- Another note as context :
-- A session can have a purchase, but not always.
-- A session with  a purchase is labeled IS_REVENUE_SESSION = TRUE
-- A session with no purchase is labeled IS_REVENUE_SESSION = FALSE

-- A visitor is anchored to their EARLIEST OBSERVED revenue session
-- inside the dataset period (not their first purchase ever).

-- Session count includes ALL observed sessions (revenue or
-- browsing) from the visitor's first observed session up to and
-- including that earliest observed revenue session.


-- ============================================================

CREATE OR REPLACE TABLE
    DASHVIO.ANALYTICS.BQ01A_VISITOR_SESSION_COUNT_LABELED AS

-- ------------------------------------------------------------
-- Step 1 - Find each visitor's earliest observed revenue session / timestamp
-- CTE name: sessions_visitor_first_revenue_session

-- This CTE tracks every visitor's session where they make a purchase.
-- A purchase is flagged by IS_REVENUE_SESSION = TRUE
-- Then we find the timestamp of that very first observable purchase session.

-- We will use this as the anchor to check prior sessions leading up to 
-- the earliest observed purchase on the next step.
-- ------------------------------------------------------------

WITH sessions_visitor_first_revenue_session AS 
(
    SELECT
        VISITOR_ID,
        MIN(VISIT_START_TIMESTAMP) AS FIRST_REVENUE_SESSION_TIMESTAMP

    FROM DASHVIO.STAGING.STG_SESSIONS
    WHERE IS_REVENUE_SESSION = TRUE
    GROUP BY VISITOR_ID
),


-- ------------------------------------------------------------
-- Step 2 - Count and label each visitor's sessions
-- CTE name: visitor_session_count_labeled
--
-- Step 1 got us the timestamp of each Visitor's first observable transaction
--
-- On this CTE, we join that back to original STG_SESSION again to find 
-- each sessions up to and including the Visitor's first observable transaction
-- 
-- Visitors with          1 session  are labeled SINGLE_SESSION
-- visitors with 2 and more sessions are labeled  MULTI_SESSION.
-- ------------------------------------------------------------

visitor_session_count_labeled AS 
(
    SELECT
        s.VISITOR_ID,
        f.FIRST_REVENUE_SESSION_TIMESTAMP,

        COUNT(*) AS SESSION_COUNT_TO_REVENUE_SESSION,

        CASE
            WHEN COUNT(*) = 1 THEN 'SINGLE_SESSION'
            ELSE 'MULTI_SESSION'
        END AS SESSION_COUNT_GROUP

    FROM DASHVIO.STAGING.STG_SESSIONS AS s

    INNER JOIN sessions_visitor_first_revenue_session AS f
        ON s.VISITOR_ID = f.VISITOR_ID

    WHERE s.VISIT_START_TIMESTAMP <= f.FIRST_REVENUE_SESSION_TIMESTAMP

    GROUP BY
        s.VISITOR_ID,
        f.FIRST_REVENUE_SESSION_TIMESTAMP
)

SELECT *
FROM visitor_session_count_labeled;