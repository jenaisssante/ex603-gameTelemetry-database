-- =================================================================
-- EX 603 Assignment 3 - q3_3.sql
-- Task 3.3: Hand the team a corrected query, written three ways
-- Database: ex603_data, loaded from the provided gaming.sql
-- Run:      psql -d ex603_data -f queries/unit3/q3_3.sql
--
-- Two-step question:
--   Step 1  Find the disputed events: ranked-match sessions that ended
--           in a network timeout.
--   Step 2  List the players involved in them (the actors whose
--           ranked rewards the payout freeze affects).
-- Every form returns 8 players. Player 1 has two disputed sessions
-- and must appear once.
-- =================================================================


-- -----------------------------------------------------------------
-- 3.3-1 FORM 1 - subquery with IN.
--      The subquery returns the player_id of every disputed session.
--      IN keeps each player whose id appears at least once.
-- -----------------------------------------------------------------
SELECT pl.player_id, pl.player_name, pl.region
FROM   players pl
WHERE  pl.player_id IN (
           SELECT p.player_id
           FROM   match_participants p
           JOIN   matches m ON m.match_id = p.match_id
           WHERE  m.is_ranked = TRUE
             AND  p.disconnect_reason = 'Network timeout'
       )
ORDER  BY pl.player_id;


-- -----------------------------------------------------------------
-- 3.3-2 FORM 2 - Common Table Expression with WITH.
--      Step 1 is named (disputed_players) and joined to players.
--      DISTINCT inside the CTE is required: without it player 1
--      would be joined twice (see 3.3-6).
-- -----------------------------------------------------------------
WITH disputed_players AS (
    SELECT DISTINCT p.player_id
    FROM   match_participants p
    JOIN   matches m ON m.match_id = p.match_id
    WHERE  m.is_ranked = TRUE
      AND  p.disconnect_reason = 'Network timeout'
)
SELECT pl.player_id, pl.player_name, pl.region
FROM   players pl
JOIN   disputed_players d ON d.player_id = pl.player_id
ORDER  BY pl.player_id;


-- -----------------------------------------------------------------
-- 3.3-3 FORM 3 - correlated subquery with EXISTS.
--      For each player, check whether at least one disputed session
--      of theirs exists. The check returns TRUE or FALSE, never
--      UNKNOWN, and stops at the first match, so duplicates never
--      reach the output.
-- -----------------------------------------------------------------
SELECT pl.player_id, pl.player_name, pl.region
FROM   players pl
WHERE  EXISTS (
           SELECT 1
           FROM   match_participants p
           JOIN   matches m ON m.match_id = p.match_id
           WHERE  p.player_id = pl.player_id
             AND  m.is_ranked = TRUE
             AND  p.disconnect_reason = 'Network timeout'
       )
ORDER  BY pl.player_id;


-- -----------------------------------------------------------------
-- 3.3-4 PROOF that the rows themselves match, not just the counts.
--      For each pair of forms, EXCEPT ALL lists rows the left form
--      returns that the right one does not. It is run in both
--      directions. EXCEPT ALL keeps duplicates, so a row repeated in
--      one form but not the other is counted as a difference too.
--      Identical result sets give 0 in both difference columns.
-- -----------------------------------------------------------------
WITH
f1 AS (
    SELECT pl.player_id, pl.player_name, pl.region
    FROM   players pl
    WHERE  pl.player_id IN (
               SELECT p.player_id
               FROM   match_participants p
               JOIN   matches m ON m.match_id = p.match_id
               WHERE  m.is_ranked = TRUE
                 AND  p.disconnect_reason = 'Network timeout')
),
f2 AS (
    SELECT pl.player_id, pl.player_name, pl.region
    FROM   players pl
    JOIN  (SELECT DISTINCT p.player_id
           FROM   match_participants p
           JOIN   matches m ON m.match_id = p.match_id
           WHERE  m.is_ranked = TRUE
             AND  p.disconnect_reason = 'Network timeout') d
      ON   d.player_id = pl.player_id
),
f3 AS (
    SELECT pl.player_id, pl.player_name, pl.region
    FROM   players pl
    WHERE  EXISTS (
               SELECT 1
               FROM   match_participants p
               JOIN   matches m ON m.match_id = p.match_id
               WHERE  p.player_id = pl.player_id
                 AND  m.is_ranked = TRUE
                 AND  p.disconnect_reason = 'Network timeout')
)
SELECT 'Form 1 vs Form 2' AS comparison,
       (SELECT COUNT(*) FROM f1) AS left_rows,
       (SELECT COUNT(*) FROM f2) AS right_rows,
       (SELECT COUNT(*) FROM (SELECT * FROM f1 EXCEPT ALL SELECT * FROM f2) x) AS only_in_left,
       (SELECT COUNT(*) FROM (SELECT * FROM f2 EXCEPT ALL SELECT * FROM f1) x) AS only_in_right
UNION ALL
SELECT 'Form 1 vs Form 3',
       (SELECT COUNT(*) FROM f1), (SELECT COUNT(*) FROM f3),
       (SELECT COUNT(*) FROM (SELECT * FROM f1 EXCEPT ALL SELECT * FROM f3) x),
       (SELECT COUNT(*) FROM (SELECT * FROM f3 EXCEPT ALL SELECT * FROM f1) x)
UNION ALL
SELECT 'Form 2 vs Form 3',
       (SELECT COUNT(*) FROM f2), (SELECT COUNT(*) FROM f3),
       (SELECT COUNT(*) FROM (SELECT * FROM f2 EXCEPT ALL SELECT * FROM f3) x),
       (SELECT COUNT(*) FROM (SELECT * FROM f3 EXCEPT ALL SELECT * FROM f2) x);


-- -----------------------------------------------------------------
-- 3.3-5 The three results side by side for all 30 players, so the
--      identity can be checked by eye: in every row the three forms
--      agree (8 'yes' rows, 22 'no' rows).
-- -----------------------------------------------------------------
SELECT pl.player_id, pl.player_name,
       CASE WHEN pl.player_id IN (
                SELECT p.player_id FROM match_participants p
                JOIN matches m ON m.match_id = p.match_id
                WHERE m.is_ranked = TRUE AND p.disconnect_reason = 'Network timeout')
            THEN 'yes' ELSE 'no' END AS in_form1_in,
       CASE WHEN pl.player_id IN (
                SELECT DISTINCT p.player_id FROM match_participants p
                JOIN matches m ON m.match_id = p.match_id
                WHERE m.is_ranked = TRUE AND p.disconnect_reason = 'Network timeout')
            THEN 'yes' ELSE 'no' END AS in_form2_cte,
       CASE WHEN EXISTS (
                SELECT 1 FROM match_participants p
                JOIN matches m ON m.match_id = p.match_id
                WHERE p.player_id = pl.player_id
                  AND m.is_ranked = TRUE AND p.disconnect_reason = 'Network timeout')
            THEN 'yes' ELSE 'no' END AS in_form3_exists
FROM   players pl
ORDER  BY pl.player_id;


-- -----------------------------------------------------------------
-- 3.3-6 Where equivalence breaks: DUPLICATES.
--      Player 1 has two disputed sessions (ids 4 and 26). IN and
--      EXISTS only test whether a match exists, so player 1 appears
--      once. A join-based CTE returns one row per matching session
--      unless it de-duplicates. Without the DISTINCT, Form 2 returns
--      9 rows, with player 1 twice, while Forms 1 and 3 still return
--      8. The query below groups that output to show which player
--      repeats. Any payout built by summing over that result
--      would pay player 1 twice.
-- -----------------------------------------------------------------
WITH disputed_sessions AS (          -- no DISTINCT
    SELECT p.player_id
    FROM   match_participants p
    JOIN   matches m ON m.match_id = p.match_id
    WHERE  m.is_ranked = TRUE
      AND  p.disconnect_reason = 'Network timeout'
)
SELECT pl.player_id, pl.player_name, COUNT(*) AS times_returned
FROM   players pl
JOIN   disputed_sessions d ON d.player_id = pl.player_id
GROUP  BY pl.player_id, pl.player_name
ORDER  BY times_returned DESC, pl.player_id;

-- A second break point, for the negated question ("players with NO
-- disputed session"): NOT IN over a column that can be NULL returns
-- nothing if a single NULL reaches the list, while NOT EXISTS still
-- answers correctly. Here the inner column (player_id) is NOT NULL,
-- so the positive forms above are safe.
