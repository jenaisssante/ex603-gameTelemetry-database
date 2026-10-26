-- =================================================================
-- EX 603 Assignment 4 - q4_1.sql
-- Task 4.1: Measure the platform
-- Theme:    Game Telemetry (events = match_participants,
--           producers = matches, metric = score,
--           failure state = network timeout)
-- Database: ex603_data, loaded from the provided gaming.sql
-- Run:      psql -d ex603_data -f queries/unit4/q4_1.sql
--
-- Failure rate definition, carried over from the Unit 3 repair:
--   network timeouts / sessions that were not a voluntary quit.
--   "Not a voluntary quit" is written IS DISTINCT FROM 'Player quit',
--   never <> 'Player quit', because 166 sessions have a NULL reason
--   and <> would silently drop them (the Unit 3 dashboard bug).
-- =================================================================


-- -----------------------------------------------------------------
-- 4.1a-1 The whole platform in one row: how many sessions were
--      recorded, the total, average, lowest and highest score, and
--      how many different players appear.
--      Requirement: COUNT, SUM, AVG, MIN, MAX, COUNT(DISTINCT).
-- Finding: 200 sessions, total score 3628.19, average 18.14, range
--      0.00 to 70.86, 30 distinct players. The minimum of 0 needs
--      explaining before the average can be trusted (see 4.1a-2).
-- -----------------------------------------------------------------
SELECT COUNT(*)                   AS sessions,
       SUM(score)                 AS total_score,
       ROUND(AVG(score), 2)       AS avg_score,
       MIN(score)                 AS min_score,
       MAX(score)                 AS max_score,
       COUNT(DISTINCT player_id)  AS distinct_players
FROM   match_participants;


-- -----------------------------------------------------------------
-- 4.1a-2 Follow-up on the zero minimum: which sessions score 0, and
--      what does the average look like without them?
--      Requirement: aggregate review of a suspicious MIN.
-- Finding: every one of the 34 abandoned sessions scores exactly 0,
--      and no finished or contested session does. A zero is not a bad
--      game; it is a session that never produced a result. Averaging
--      those zeros in drags the platform average from 21.86 (sessions
--      that produced a result) down to 18.14, so any match with more
--      failures looks like it has weaker players.
-- -----------------------------------------------------------------
SELECT participation_status,
       COUNT(*)              AS sessions,
       MIN(score)            AS min_score,
       MAX(score)            AS max_score,
       ROUND(AVG(score), 2)  AS avg_score
FROM   match_participants
GROUP  BY participation_status
ORDER  BY sessions DESC;


-- -----------------------------------------------------------------
-- 4.1b Activity and performance per producer: how many sessions each
--      match recorded and its average score, busiest match first.
--      Requirement: GROUP BY producer, COUNT, AVG, ORDER BY count DESC.
--      LEFT JOIN from matches so a match with no sessions still shows.
-- Finding: volume ranges from 21 sessions (match 6) to 0 (matches 14
--      and 15, which an inner join would hide entirely). Match 11 has
--      the lowest average score of any populated match, 11.94, against
--      a platform average of 18.14. Match 6 is listed with a
--      player_count of 4 but recorded 21 sessions, so player_count is
--      a configured lobby size, not attendance.
-- -----------------------------------------------------------------
SELECT m.match_id,
       m.server_region,
       CASE WHEN m.is_ranked THEN 'Ranked' ELSE 'Casual' END  AS match_type,
       COUNT(p.participation_id)                             AS sessions,
       ROUND(AVG(p.score), 2)                                AS avg_score
FROM   matches m
LEFT   JOIN match_participants p ON p.match_id = m.match_id
GROUP  BY m.match_id, m.server_region, m.is_ranked
ORDER  BY sessions DESC, m.match_id;


-- -----------------------------------------------------------------
-- 4.1c-1 Which matches have enough sessions for their timeout rate to
--      mean anything? Threshold: at least 15 sessions.
--      Requirement: HAVING on an aggregate.
-- Why 15: the platform timeout rate is about 6%. At 15 sessions a
--      single timeout reads as 6.7%, roughly the platform norm, so one
--      isolated event cannot make a match look abnormal. Below 15 one
--      timeout already reads as 7.1% or more, and the rate measures
--      luck, not the match. 15 is also just under the median volume
--      of the populated matches (16).
-- Finding: 8 of the 15 matches qualify, covering 145 of 200 sessions.
--      Among them, match 2 stands out with 3 timeouts in 16 sessions.
-- -----------------------------------------------------------------
SELECT m.match_id,
       m.server_region,
       COUNT(*)                                                        AS sessions,
       ROUND(AVG(p.score), 2)                                          AS avg_score,
       SUM(CASE WHEN p.disconnect_reason = 'Network timeout' THEN 1 ELSE 0 END) AS timeouts,
       ROUND(100.0
           * SUM(CASE WHEN p.disconnect_reason = 'Network timeout' THEN 1 ELSE 0 END)
           / NULLIF(COUNT(CASE WHEN p.disconnect_reason IS DISTINCT FROM 'Player quit'
                               THEN 1 END), 0), 1)                     AS timeout_rate_pct
FROM   match_participants p
JOIN   matches m ON m.match_id = p.match_id
GROUP  BY m.match_id, m.server_region
HAVING COUNT(*) >= 15
ORDER  BY sessions DESC, m.match_id;


-- -----------------------------------------------------------------
-- 4.1c-2 What the threshold set aside: the matches below 15 sessions,
--      shown so the cut is visible rather than silent.
--      Requirement: HAVING (the complement of 4.1c-1).
-- Finding: 5 matches with sessions fall below the bar. Match 4 shows
--      1 timeout in 5 eligible sessions (20%) and match 3 shows 2 in
--      13 (15.4%). Both rates rest on one or two events. Matches 14
--      and 15 have no sessions and do not appear here at all.
-- -----------------------------------------------------------------
SELECT m.match_id,
       m.server_region,
       COUNT(*)                                                        AS sessions,
       SUM(CASE WHEN p.disconnect_reason = 'Network timeout' THEN 1 ELSE 0 END) AS timeouts,
       ROUND(100.0
           * SUM(CASE WHEN p.disconnect_reason = 'Network timeout' THEN 1 ELSE 0 END)
           / NULLIF(COUNT(CASE WHEN p.disconnect_reason IS DISTINCT FROM 'Player quit'
                               THEN 1 END), 0), 1)                     AS timeout_rate_pct
FROM   match_participants p
JOIN   matches m ON m.match_id = p.match_id
GROUP  BY m.match_id, m.server_region
HAVING COUNT(*) < 15
ORDER  BY sessions DESC, m.match_id;


-- -----------------------------------------------------------------
-- 4.1d Two dimensions at once: server region by match type (ranked
--      or casual). One row per combination, so each regional lead can
--      find their own ranked and casual numbers.
--      Requirement: GROUP BY two dimensions, including region.
--      Region is the match's server_region (where the match is
--      hosted), not the player's client_region: the question is about
--      the regions' infrastructure, and the two disagree on 160 of 200
--      sessions.
-- Finding: 7 combinations. Casual play exists only in EU and OCE.
--      APAC ranked holds 5 of the 12 timeouts. NA ranked recorded 19
--      sessions with no timeouts, but all 19 come from a single match.
-- -----------------------------------------------------------------
SELECT m.server_region,
       CASE WHEN m.is_ranked THEN 'Ranked' ELSE 'Casual' END  AS match_type,
       COUNT(DISTINCT m.match_id)                            AS matches,
       COUNT(*)                                              AS sessions,
       COUNT(DISTINCT p.player_id)                           AS distinct_players,
       ROUND(AVG(p.score), 2)                                AS avg_score,
       MIN(p.score)                                          AS min_score,
       MAX(p.score)                                          AS max_score,
       SUM(CASE WHEN p.disconnect_reason = 'Network timeout' THEN 1 ELSE 0 END) AS timeouts
FROM   match_participants p
JOIN   matches m ON m.match_id = p.match_id
GROUP  BY m.server_region, m.is_ranked
ORDER  BY m.server_region, match_type DESC;
