-- =================================================================
-- EX 603 Assignment 4 - q4_2.sql
-- Task 4.2: Build the breakdown leadership asked for
-- Database: ex603_data, loaded from the provided gaming.sql
-- Run:      psql -d ex603_data -f queries/unit4/q4_2.sql
--
-- Failure  = disconnect_reason = 'Network timeout'.
-- Eligible = every session that was not a voluntary quit, written
--            disconnect_reason IS DISTINCT FROM 'Player quit' so the
--            166 NULL-reason sessions stay in (the Unit 3 repair).
-- Platform-side drop = any abandonment the player did not choose:
--            network timeout, server restart or client crash.
-- =================================================================


-- =================================================================
-- PART A - Two numbers in one pass
-- =================================================================

-- -----------------------------------------------------------------
-- 4.2a For every match: how many sessions it recorded, and how many
--      of those ended in a network timeout - side by side, from one
--      read of the event table and no WHERE clause.
--      Requirement: CASE inside an aggregate; both totals as separate
--      columns in one result set.
--      Extra columns from the same pass: sessions eligible for the
--      rate, the timeout rate, and all platform-side drops.
-- Finding: 12 timeouts across 13 matches. Match 2 has 3 of them in 16
--      sessions (18.8%), a quarter of every timeout on the platform.
--      Match 11 has only 1 timeout but 4 platform-side drops in 15
--      eligible sessions, tied with matches 2 and 9 for the most.
--      Match 3 (2 in 13) and match 4 (1 in 5) show high rates on low
--      volume; 4.1c set them aside for that reason.
--      Matches 5, 8, 10 and 13 recorded no timeouts at all.
-- -----------------------------------------------------------------
SELECT match_id,
       COUNT(*)                                                       AS total_sessions,
       SUM(CASE WHEN disconnect_reason = 'Network timeout'
                THEN 1 ELSE 0 END)                                    AS timeout_sessions,
       COUNT(CASE WHEN disconnect_reason IS DISTINCT FROM 'Player quit'
                  THEN 1 END)                                         AS eligible_sessions,
       ROUND(100.0
           * SUM(CASE WHEN disconnect_reason = 'Network timeout' THEN 1 ELSE 0 END)
           / NULLIF(COUNT(CASE WHEN disconnect_reason IS DISTINCT FROM 'Player quit'
                               THEN 1 END), 0), 1)                    AS timeout_rate_pct,
       SUM(CASE WHEN disconnect_reason IN ('Network timeout',
                                           'Server restart',
                                           'Client crash')
                THEN 1 ELSE 0 END)                                    AS platform_drops
FROM   match_participants
GROUP  BY match_id
ORDER  BY timeout_sessions DESC, timeout_rate_pct DESC, match_id;


-- =================================================================
-- PART B - Subtotals and a grand total
-- =================================================================

-- -----------------------------------------------------------------
-- 4.2b Regional subtotals and one platform grand total, with no
--      per-match detail rows - the view a regional director reads.
--      Requirement: GROUP BY ROLLUP.
--      ROLLUP (server_region) produces one row per region plus one
--      row where server_region has been rolled up to "all regions".
--      GROUPING(server_region) is 1 only on that rolled-up row, so
--      the row_type column labels it instead of leaving a bare NULL.
--      How to read the output:
--        row_type = 'Regional subtotal'    -> the five region rows
--        row_type = 'Platform grand total' -> the last row
--      LEFT JOIN from matches so the empty matches 14 and 15 still
--      count toward their region's match total. The eligible count
--      tests participation_id IS NOT NULL first; otherwise the NULL
--      row a LEFT JOIN produces for an empty match would count as an
--      eligible session.
-- Finding: grand total 15 matches, 200 sessions, 193 eligible,
--      12 timeouts = 6.2%, 27 platform-side drops = 14.0%.
--      APAC carries the most: 5 of the 12 timeouts (9.8%) and 11 of
--      the 27 drops (21.6%) on 51 eligible sessions. EU's rates are
--      higher (10.5% and 26.3%) but rest on 19 sessions from two
--      low-volume matches. NA has no timeouts or drops at all.
-- -----------------------------------------------------------------
SELECT CASE WHEN GROUPING(m.server_region) = 1
            THEN 'Platform grand total'
            ELSE 'Regional subtotal' END                              AS row_type,
       COALESCE(m.server_region, 'ALL REGIONS')                       AS server_region,
       COUNT(DISTINCT m.match_id)                                     AS matches,
       COUNT(p.participation_id)                                      AS sessions,
       COUNT(CASE WHEN p.participation_id IS NOT NULL
                   AND p.disconnect_reason IS DISTINCT FROM 'Player quit'
                  THEN 1 END)                                         AS eligible_sessions,
       SUM(CASE WHEN p.disconnect_reason = 'Network timeout'
                THEN 1 ELSE 0 END)                                    AS timeouts,
       ROUND(100.0
           * SUM(CASE WHEN p.disconnect_reason = 'Network timeout' THEN 1 ELSE 0 END)
           / NULLIF(COUNT(CASE WHEN p.participation_id IS NOT NULL
                                AND p.disconnect_reason IS DISTINCT FROM 'Player quit'
                               THEN 1 END), 0), 1)                    AS timeout_rate_pct,
       SUM(CASE WHEN p.disconnect_reason IN ('Network timeout',
                                             'Server restart',
                                             'Client crash')
                THEN 1 ELSE 0 END)                                    AS platform_drops,
       ROUND(100.0
           * SUM(CASE WHEN p.disconnect_reason IN ('Network timeout',
                                                   'Server restart',
                                                   'Client crash')
                      THEN 1 ELSE 0 END)
           / NULLIF(COUNT(CASE WHEN p.participation_id IS NOT NULL
                                AND p.disconnect_reason IS DISTINCT FROM 'Player quit'
                               THEN 1 END), 0), 1)                    AS drop_rate_pct
FROM   matches m
LEFT   JOIN match_participants p ON p.match_id = m.match_id
GROUP  BY ROLLUP (m.server_region)
ORDER  BY GROUPING(m.server_region), m.server_region;


-- =================================================================
-- PART C - A two-step pipeline
-- =================================================================

-- -----------------------------------------------------------------
-- 4.2c-1 What does normal look like for a high-volume match?
--      Step 1 (per_match): summarise every match from the event table.
--      Step 2: keep the matches with at least 15 sessions (the 4.1c
--      threshold) and aggregate them again into one baseline row.
--      Requirement: WITH clause producing an intermediate aggregate;
--      a second aggregation over it.
--      pooled rate = all their timeouts / all their eligible sessions
--      (every session weighs the same). mean of match rates = the
--      average of each match's own rate (every match weighs the same).
--      The pooled rate is the baseline; the mean is shown beside it
--      as a check that no single match is distorting the pool.
-- Finding: 8 high-volume matches, 145 sessions, 140 eligible.
--      Baseline timeout rate 5.0% (pooled) vs 5.3% (mean of matches).
--      Baseline platform-side drop rate 12.1%.
-- -----------------------------------------------------------------
WITH per_match AS (
    SELECT match_id,
           COUNT(*)                                                   AS sessions,
           COUNT(CASE WHEN disconnect_reason IS DISTINCT FROM 'Player quit'
                      THEN 1 END)                                     AS eligible,
           SUM(CASE WHEN disconnect_reason = 'Network timeout'
                    THEN 1 ELSE 0 END)                                AS timeouts,
           SUM(CASE WHEN disconnect_reason IN ('Network timeout',
                                               'Server restart',
                                               'Client crash')
                    THEN 1 ELSE 0 END)                                AS platform_drops
    FROM   match_participants
    GROUP  BY match_id
)
SELECT COUNT(*)                                                       AS high_volume_matches,
       SUM(sessions)                                                  AS sessions,
       SUM(eligible)                                                  AS eligible_sessions,
       SUM(timeouts)                                                  AS timeouts,
       ROUND(100.0 * SUM(timeouts) / SUM(eligible), 1)                AS baseline_timeout_pct,
       ROUND(AVG(100.0 * timeouts / eligible), 1)                     AS mean_of_match_rates_pct,
       ROUND(100.0 * SUM(platform_drops) / SUM(eligible), 1)          AS baseline_drop_pct
FROM   per_match
WHERE  sessions >= 15;


-- -----------------------------------------------------------------
-- 4.2c-2 The same pipeline carried one step further: each
--      high-volume match against the baseline, so the outliers name
--      themselves. A match is flagged when either its timeout rate or
--      its platform-side drop rate is at least twice the baseline.
--      Requirement: WITH (three chained CTEs), a filter and a second
--      aggregation over the intermediate result.
-- Finding: two matches are flagged, both hosted in APAC.
--      Match 2: timeouts 18.8% vs 5.0% baseline (3.8x), drops 25.0%.
--      Match 11: timeouts 6.7%, near baseline, but drops 26.7% vs
--      12.1% (2.2x). Every other high-volume match sits at or below
--      1.2x the baseline on both measures.
-- -----------------------------------------------------------------
WITH per_match AS (
    SELECT match_id,
           COUNT(*)                                                   AS sessions,
           COUNT(CASE WHEN disconnect_reason IS DISTINCT FROM 'Player quit'
                      THEN 1 END)                                     AS eligible,
           SUM(CASE WHEN disconnect_reason = 'Network timeout'
                    THEN 1 ELSE 0 END)                                AS timeouts,
           SUM(CASE WHEN disconnect_reason IN ('Network timeout',
                                               'Server restart',
                                               'Client crash')
                    THEN 1 ELSE 0 END)                                AS platform_drops
    FROM   match_participants
    GROUP  BY match_id
),
high_volume AS (
    SELECT *
    FROM   per_match
    WHERE  sessions >= 15
),
baseline AS (
    SELECT 100.0 * SUM(timeouts)       / SUM(eligible)                AS timeout_pct,
           100.0 * SUM(platform_drops) / SUM(eligible)                AS drop_pct
    FROM   high_volume
)
SELECT h.match_id,
       h.sessions,
       h.timeouts,
       ROUND(100.0 * h.timeouts / h.eligible, 1)                      AS timeout_pct,
       ROUND(b.timeout_pct, 1)                                        AS baseline_timeout_pct,
       ROUND((100.0 * h.timeouts / h.eligible) / b.timeout_pct, 1)    AS timeout_x_baseline,
       h.platform_drops,
       ROUND(100.0 * h.platform_drops / h.eligible, 1)                AS drop_pct,
       ROUND(b.drop_pct, 1)                                           AS baseline_drop_pct,
       ROUND((100.0 * h.platform_drops / h.eligible) / b.drop_pct, 1) AS drop_x_baseline,
       CASE WHEN 100.0 * h.timeouts       / h.eligible >= 2 * b.timeout_pct
              OR 100.0 * h.platform_drops / h.eligible >= 2 * b.drop_pct
            THEN 'INVESTIGATE'
            ELSE 'within normal range' END                            AS assessment
FROM   high_volume h
CROSS  JOIN baseline b
ORDER  BY GREATEST((100.0 * h.timeouts       / h.eligible) / b.timeout_pct,
                   (100.0 * h.platform_drops / h.eligible) / b.drop_pct) DESC,
          h.match_id;
