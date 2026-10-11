-- =================================================================
-- EX 603 Assignment 3 - q3_1.sql
-- Task 3.1: Establish what the data contains
-- Theme:    Game Telemetry (events = match_participants,
--           producers = matches, failure state = network timeout)
-- Database: ex603_data, loaded from the provided gaming.sql
-- Run:      psql -d ex603_data -f queries/unit3/q3_1.sql
-- =================================================================


-- -----------------------------------------------------------------
-- 3.1a Ranked, well-populated matches - the producers whose sessions
--      feed ranked-mode rewards. Theme filter: is_ranked AND
--      player_count >= 8. Requirement: SELECT, WHERE, ORDER BY, LIMIT.
-- Finding: 9 of the 15 matches pass the filter, so the first ten
--      returns all 9. They hold player_count 8 to 16.
-- -----------------------------------------------------------------
SELECT match_id, match_label, server_region, player_count, scheduled_on
FROM   matches
WHERE  is_ranked = TRUE
  AND  player_count >= 8
ORDER  BY player_count DESC, match_id
LIMIT  10;


-- -----------------------------------------------------------------
-- 3.1b Every status a participation can end in, and how often.
--      Requirement: DISTINCT on the event status column.
-- Finding: three statuses, not two. Besides 'finished' and
--      'abandoned' there is 'contested' (10 rows) - a result under
--      dispute that is neither a clean finish nor a failure.
-- -----------------------------------------------------------------
SELECT DISTINCT participation_status
FROM   match_participants
ORDER  BY participation_status;

-- 3.1b (cont.) How each status breaks down by disconnect reason.
-- Finding: only 'abandoned' rows carry a reason. Network timeout is
--      12 of 200 sessions. The 166 finished and contested sessions
--      have no reason at all: disconnect_reason is NULL for them.
SELECT participation_status,
       disconnect_reason,
       COUNT(*) AS sessions
FROM   match_participants
GROUP  BY participation_status, disconnect_reason
ORDER  BY participation_status, disconnect_reason;


-- -----------------------------------------------------------------
-- 3.1c-1 Long sessions in a numeric range: 25 to 30 minutes played.
--      Requirement: filter a numeric range (BETWEEN).
-- Finding: 16 sessions. 2 of them were abandoned, both by a network
--      timeout more than 25 minutes in, scoring 0. A late timeout
--      throws away a long session's worth of play.
-- -----------------------------------------------------------------
SELECT participation_id, player_id, match_id, duration_min, score, participation_status
FROM   match_participants
WHERE  duration_min BETWEEN 25 AND 30
ORDER  BY duration_min DESC;

-- 3.1c-2 Platform-side failures: an explicit list of reasons with IN.
--      Requirement: filter using IN.
-- Finding: 20 sessions ended in a network timeout (12) or a server
--      restart (8). That is 10% of all 200 sessions, even counting
--      both platform-side causes together.
SELECT participation_id, player_id, match_id,
       participation_status, disconnect_reason
FROM   match_participants
WHERE  disconnect_reason IN ('Network timeout', 'Server restart')
ORDER  BY disconnect_reason, participation_id;


-- -----------------------------------------------------------------
-- 3.1d-1 Producers whose label matches a text pattern: Match_10 to
--      Match_15. Requirement: LIKE.
--      The underscore is escaped because a bare _ in LIKE matches
--      any single character.
-- Finding: 6 matches. Matches 14 and 15 have no participants at all,
--      which matters for the equivalence tests in q3_3.sql.
-- -----------------------------------------------------------------
SELECT m.match_id, m.match_label, m.is_ranked, m.player_count,
       COUNT(p.participation_id) AS sessions_recorded
FROM   matches m
LEFT   JOIN match_participants p ON p.match_id = m.match_id
WHERE  m.match_label LIKE 'Match\_1%'
GROUP  BY m.match_id, m.match_label, m.is_ranked, m.player_count
ORDER  BY m.match_id;

-- 3.1d-2 Sessions with no recorded disconnect reason (NULL).
--      Requirement: identify missing values with IS NULL.
-- Finding: 166 of 200 sessions (83%) have a NULL reason. This is the
--      column the dashboard filters on.
SELECT COUNT(*) AS sessions_with_no_reason
FROM   match_participants
WHERE  disconnect_reason IS NULL;

-- 3.1d-3 The same column with the gap labelled for a reader.
--      Requirement: COALESCE to replace NULL with a useful label.
-- Finding: 'No reason provided' is the largest group by far (166);
--      network timeout is 12.
SELECT COALESCE(disconnect_reason, 'No reason provided') AS disconnect_reason,
       COUNT(*) AS sessions
FROM   match_participants
GROUP  BY COALESCE(disconnect_reason, 'No reason provided')
ORDER  BY sessions DESC, disconnect_reason;


-- -----------------------------------------------------------------
-- 3.1e A session report a non-SQL reader can scan: XP earned, time
--      of day, outcome and performance band.
--      Requirement: computed columns and CASE.
--        xp_earned    = score x the session's XP multiplier
--        time_of_day  = from the hour the player joined
--        outcome      = status and reason in plain language
--        performance  = score band
-- Finding: every timed-out session shows 0 XP. A network timeout
--      costs the player the whole session's reward.
-- -----------------------------------------------------------------
SELECT p.participation_id,
       pl.player_name,
       m.match_label,
       CASE WHEN m.is_ranked THEN 'Ranked' ELSE 'Casual' END AS match_type,
       ROUND(p.score * p.xp_multiplier, 2)                    AS xp_earned,
       CASE
           WHEN EXTRACT(HOUR FROM p.joined_at) BETWEEN 5  AND 11 THEN 'Morning'
           WHEN EXTRACT(HOUR FROM p.joined_at) BETWEEN 12 AND 16 THEN 'Afternoon'
           WHEN EXTRACT(HOUR FROM p.joined_at) BETWEEN 17 AND 21 THEN 'Evening'
           ELSE 'Night'
       END                                                    AS time_of_day,
       CASE
           WHEN p.participation_status = 'finished'  THEN 'Completed'
           WHEN p.participation_status = 'contested' THEN 'Result under review'
           WHEN p.disconnect_reason = 'Network timeout' THEN 'Lost connection'
           WHEN p.disconnect_reason = 'Player quit'     THEN 'Left voluntarily'
           ELSE 'Dropped (' || COALESCE(p.disconnect_reason, 'no reason') || ')'
       END                                                    AS outcome,
       CASE
           WHEN p.score = 0   THEN 'No score'
           WHEN p.score < 15  THEN 'Low'
           WHEN p.score < 30  THEN 'Solid'
           ELSE 'Strong'
       END                                                    AS performance
FROM   match_participants p
JOIN   players pl ON pl.player_id = p.player_id
JOIN   matches m  ON m.match_id  = p.match_id
ORDER  BY p.participation_id
LIMIT  10;
