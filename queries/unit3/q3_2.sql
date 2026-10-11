-- =================================================================
-- EX 603 Assignment 3 - q3_2.sql
-- Task 3.2: Find the bug
-- Database: ex603_data, loaded from the provided gaming.sql
-- Run:      psql -d ex603_data -f queries/unit3/q3_2.sql
--
-- Part B intentionally contains one failing statement (3.2b-1).
-- psql reports the error and carries on, so the file runs from top to
-- bottom with no editing. Do not run it with ON_ERROR_STOP=1.
-- =================================================================


-- =================================================================
-- PART A - The rows that vanished
-- Nullable column: match_participants.disconnect_reason.
-- It is filled in only when a session is abandoned. Finished and
-- contested sessions leave it NULL. No NULLs were inserted; the
-- dataset already has 166 of them.
-- =================================================================

-- -----------------------------------------------------------------
-- 3.2a-1 BROKEN. Intended question: "every session except the ones
--      where the player chose to quit". That is the population the
--      timeout rate should be measured over, because a voluntary quit
--      is not a platform failure.
--      Predicate: disconnect_reason <> 'Player quit'
-- Result: 27 rows. Expected 193 (200 sessions minus 7 quits).
-- -----------------------------------------------------------------
SELECT COUNT(*) AS sessions_kept_by_broken_filter
FROM   match_participants
WHERE  disconnect_reason <> 'Player quit';


-- -----------------------------------------------------------------
-- 3.2a-2 What the broken filter dropped without warning, set beside
--      the table total. The filter (27) and its exact opposite (7)
--      should together cover every row (200). They cover 34.
--      The other 166 are rows where disconnect_reason IS NULL:
--      'NULL <> ''Player quit''' evaluates to UNKNOWN, and WHERE keeps
--      only TRUE.
-- -----------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM match_participants)                    AS table_total,
    (SELECT COUNT(*) FROM match_participants
      WHERE disconnect_reason <> 'Player quit')                  AS kept_by_filter,
    (SELECT COUNT(*) FROM match_participants
      WHERE disconnect_reason =  'Player quit')                  AS opposite_of_filter,
    (SELECT COUNT(*) FROM match_participants
      WHERE disconnect_reason <> 'Player quit')
  + (SELECT COUNT(*) FROM match_participants
      WHERE disconnect_reason =  'Player quit')                  AS kept_plus_opposite,
    (SELECT COUNT(*) FROM match_participants
      WHERE disconnect_reason IS NULL)                           AS silently_omitted;


-- -----------------------------------------------------------------
-- 3.2a-3 REPAIRED, three equivalent ways. Each returns 193.
--   (i)   an explicit IS NULL branch,
--   (ii)  COALESCE, which swaps NULL for a value the comparison can
--         handle,
--   (iii) IS DISTINCT FROM, the null-safe "not equal".
-- -----------------------------------------------------------------
SELECT COUNT(*) AS repaired_is_null
FROM   match_participants
WHERE  disconnect_reason <> 'Player quit'
   OR  disconnect_reason IS NULL;

SELECT COUNT(*) AS repaired_coalesce
FROM   match_participants
WHERE  COALESCE(disconnect_reason, 'No reason provided') <> 'Player quit';

SELECT COUNT(*) AS repaired_distinct_from
FROM   match_participants
WHERE  disconnect_reason IS DISTINCT FROM 'Player quit';

-- Check: the repaired filter plus its opposite now covers the table.
SELECT
    (SELECT COUNT(*) FROM match_participants
      WHERE disconnect_reason IS DISTINCT FROM 'Player quit')
  + (SELECT COUNT(*) FROM match_participants
      WHERE disconnect_reason = 'Player quit')                   AS repaired_plus_opposite,
    (SELECT COUNT(*) FROM match_participants)                    AS table_total;


-- -----------------------------------------------------------------
-- 3.2a-4 What the bug does to the dashboard number.
--      Our reconstruction of the dashboard metric: network-timeout
--      rate in ranked matches, excluding voluntary quits from the
--      denominator. Same numerator both times; only the denominator
--      filter changes.
-- Result: broken 9 / 20 = 45.0% ("about half").
--         repaired 9 / 166 = 5.4%.
-- -----------------------------------------------------------------
SELECT
    'broken'                                                     AS version,
    COUNT(*) FILTER (WHERE p.disconnect_reason = 'Network timeout') AS timeouts,
    COUNT(*) FILTER (WHERE p.disconnect_reason <> 'Player quit')    AS sessions_counted,
    ROUND(100.0
        * COUNT(*) FILTER (WHERE p.disconnect_reason = 'Network timeout')
        / COUNT(*) FILTER (WHERE p.disconnect_reason <> 'Player quit'), 1) AS timeout_rate_pct
FROM   match_participants p
JOIN   matches m ON m.match_id = p.match_id
WHERE  m.is_ranked = TRUE
UNION ALL
SELECT
    'repaired',
    COUNT(*) FILTER (WHERE p.disconnect_reason = 'Network timeout'),
    COUNT(*) FILTER (WHERE p.disconnect_reason IS DISTINCT FROM 'Player quit'),
    ROUND(100.0
        * COUNT(*) FILTER (WHERE p.disconnect_reason = 'Network timeout')
        / COUNT(*) FILTER (WHERE p.disconnect_reason IS DISTINCT FROM 'Player quit'), 1)
FROM   match_participants p
JOIN   matches m ON m.match_id = p.match_id
WHERE  m.is_ranked = TRUE;


-- =================================================================
-- PART B - The alias that did not exist yet
-- Logical evaluation order: FROM -> WHERE -> GROUP BY -> HAVING ->
-- SELECT -> ORDER BY. WHERE is evaluated before SELECT, so a column
-- alias defined in SELECT does not exist yet when WHERE runs.
-- =================================================================

-- -----------------------------------------------------------------
-- 3.2b-1 BROKEN. Question: which sessions earned more than 50 XP?
--      The alias xp_earned is defined in SELECT and used in WHERE.
-- Verbatim error (PostgreSQL 16):
--   ERROR:  column "xp_earned" does not exist
--   LINE 3: WHERE  xp_earned > 50
--                  ^
-- -----------------------------------------------------------------
SELECT participation_id, player_id, ROUND(score * xp_multiplier, 2) AS xp_earned
FROM   match_participants
WHERE  xp_earned > 50
ORDER  BY xp_earned DESC;


-- -----------------------------------------------------------------
-- 3.2b-2 REWRITE 1: repeat the expression in WHERE.
--      ORDER BY runs after SELECT, so the alias is valid there.
-- Result: 20 sessions.
-- -----------------------------------------------------------------
SELECT participation_id, player_id, ROUND(score * xp_multiplier, 2) AS xp_earned
FROM   match_participants
WHERE  ROUND(score * xp_multiplier, 2) > 50
ORDER  BY xp_earned DESC;


-- -----------------------------------------------------------------
-- 3.2b-3 REWRITE 2: compute xp_earned in a CTE so that it becomes a
--      real column the outer WHERE can see.
-- Result: the same 20 sessions.
-- -----------------------------------------------------------------
WITH session_xp AS (
    SELECT participation_id, player_id, ROUND(score * xp_multiplier, 2) AS xp_earned
    FROM   match_participants
)
SELECT participation_id, player_id, xp_earned
FROM   session_xp
WHERE  xp_earned > 50
ORDER  BY xp_earned DESC;
