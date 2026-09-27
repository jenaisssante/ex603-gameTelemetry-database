# Unit 2 — From ERD to DDL (Task 2.2)

The DDL is in [`schema/schema.sql`](../schema/schema.sql). It runs top to bottom
on an empty PostgreSQL 14+ database and can be run again straight away, because
it opens with a reset block that drops the tables in reverse creation order.

## Creation order

| # | Table | References | Why it sits here |
|---|-------|------------|------------------|
| 1 | players | — | No outgoing foreign keys. |
| 2 | game_modes | game_modes (itself) | Its only foreign key points at itself, and a self-reference is resolved inside one `CREATE TABLE`. |
| 3 | matches | — | No outgoing foreign keys. |
| 4 | match_modes | matches, game_modes | Both parents must already exist. |
| 5 | match_participants | matches, players | Both parents must already exist. |

## Changes from the Unit 1 design

Building the DDL changed the design in three ways. The ERD (`schema/erd.dbml`
and `schema/erd.png`) has been updated to match.

1. **A recursive foreign key on `game_modes`.** The Unit 1 design had no
   self-referencing relationship. I added `game_modes.parent_mode_id`, which
   points at the mode family a mode belongs to ('Ranked Solo' and 'Ranked Duo'
   under 'Ranked'). It sits on `game_modes` because that is the only entity in
   this domain with a real hierarchy. Players have no natural parent, and
   matches do not nest. The hierarchy also answers a question the platform
   already asks, "which game modes are played most often?", at the family
   level as well as for single modes. A top-level mode has
   `parent_mode_id = NULL`.
2. **Types aligned to the course mapping.** Unit 1 sized the keys by expected
   volume (`SMALLINT` for modes, `BIGINT` for matches) and used `TIMESTAMPTZ`.
   The DDL follows the Unit 2 type mapping instead: every surrogate key is
   `INTEGER GENERATED ALWAYS AS IDENTITY` and every point in time is
   `TIMESTAMP`. Using one key type means every foreign key column matches its
   parent exactly. `INTEGER` still allows about 2.1 billion matches, far more
   than this project will ever hold. Timestamps are recorded in server time
   (UTC).
3. **Two non-blank CHECKs.** `display_name` and `mode_name` were already
   `NOT NULL`, but `NOT NULL` still accepts an empty or all-space string. Two
   CHECK constraints now reject those values (see below).

All primary keys, the other four foreign keys, their `ON DELETE` actions, the
`UNIQUE` on `mode_name` and the three Unit 1 CHECKs are unchanged.

**Derived values.** No derived value is stored. A match's end time
(`started_at + duration_sec`) and every aggregate the later units need (average
score per player, match count per mode) are computed at query time. The
aggregates can't be `GENERATED` columns, because a generated column can only
read its own row, and these values change every time a result row arrives.
Storing them would mean a trigger or application code keeping a copy in sync,
and any copy can drift from the source rows. End time could be generated, but it
is a cheap addition in any query that needs it, so storing it adds a column
without adding information.

## Constraints table

| Foreign key | ON DELETE | Reason |
|-------------|-----------|--------|
| `match_participants.match_id → matches` | CASCADE | A result only means something as part of its match, so it is deleted along with the match. |
| `match_participants.player_id → players` | RESTRICT | Deleting a player who has results would quietly change historical leaderboards and averages. |
| `match_modes.match_id → matches` | CASCADE | A mode tag describes one match and has no meaning once that match is gone. |
| `match_modes.game_mode_id → game_modes` | RESTRICT | A mode still used to classify matches is reference data and cannot be removed underneath them. |
| `game_modes.parent_mode_id → game_modes` | RESTRICT | Removing a mode family must not silently turn its child modes into top-level modes. |

### What each choice governs

**`match_participants.match_id`: CASCADE.** On this platform a match is deleted
when it is voided: a server crash mid-game, a match played on a test build, or
one that an anti-cheat review annuls. When that happens, every player's score
from that match has to come out of the leaderboards too. That is the reason for
voiding it. CASCADE removes the match and all of its results in one statement,
so the ladder and the match-history screen stay consistent with each other.
Under RESTRICT, voiding would need two steps, deleting the results and then the
match. If the job stopped between the two, the database would hold scores for
a match that no longer exists. SET NULL is not possible here, because
`match_id` is part of the primary key.

**`match_participants.player_id`: RESTRICT.** A player is removed when an
account is closed or banned. Those players' results are also the other players'
opponents. Cascading the delete would change the recorded outcome of every
match they played in: a 2v2 would suddenly show one player on a side, and every
opponent's historical average would move. RESTRICT stops the delete. Account
closure is handled by anonymising the player row (for example, setting
`display_name` to 'Deleted Player'), which keeps the history correct and
removes the personal information. SET NULL is not possible because `player_id`
is part of the primary key.

**`match_modes.match_id`: CASCADE.** When a match is voided, its tags ("this was
Ranked Solo") go with it. A tag pointing at a missing match would count toward
"most played mode" statistics for a game that officially never happened.
RESTRICT would make voiding a match need an extra cleanup step for no benefit.

**`match_modes.game_mode_id`: RESTRICT.** A mode is removed when designers retire
it, for example when a limited-time event mode ends. Those matches were still
played in that mode, and the history should say so. Under CASCADE, retiring
the event would delete every tag for it. Those matches would then have no mode
at all, and "most played mode" figures for past seasons would shift. RESTRICT
makes a retired mode stay in the catalog as long as any match refers to it.
Taking it off the in-game menu is an application concern, not a delete.

**`game_modes.parent_mode_id`: RESTRICT.** This choice governs removing a mode
family such as 'Ranked'. SET NULL looks harmless because the child modes would
survive, but they would become top-level modes without anyone deciding that.
Every family-level rollup ("Ranked matches this season") would then drop them
without any error. CASCADE is worse. It would delete the child modes
along with the family, or, if any child still tags a match, fail with an error
from a different constraint that does not explain the real cause. With RESTRICT, whoever
removes a family has to reassign or retire its child modes first, so the
hierarchy only changes when someone changes it deliberately. This follows the
same principle as the rest of the schema: a delete must never quietly rewrite
historical aggregates.

## CHECK constraints

**`chk_match_participants_score_nonnegative`: `score >= 0`.** Makes a negative
score unstorable. One could otherwise come from a scoring bug that subtracts
penalties past zero, from a signed/unsigned mismatch in the game server's
telemetry payload, or from a hand-edited correction. A single negative row
would pull down that player's average and could put them below zero on a
leaderboard that is supposed to start at zero.

**`chk_matches_duration_nonnegative`: `duration_sec IS NULL OR duration_sec >= 0`.**
Makes a negative match length unstorable. One could come from computing
duration as end time minus start time when the two clocks disagree, or when a
server's clock is corrected in the middle of a match. The `IS NULL` branch is
required because a live match has no duration yet.

**`chk_matches_active_duration_consistent`: `(is_active AND duration_sec IS NULL) OR (NOT is_active AND duration_sec IS NOT NULL)`.**
Makes the two contradictory match states unstorable: a live match that already
has a final duration, and a completed match with none. The first could come
from a writer that records the duration but crashes before clearing
`is_active`. The second could come from marking a match finished without
recording how long it lasted. Either one would give different answers to
"how many matches are still active?" depending on which column a query checks.
The constraint makes the two columns change together or not at all.

**`chk_game_modes_no_self_parent`: `parent_mode_id IS DISTINCT FROM game_mode_id`.**
Makes a mode that is its own parent unstorable. That could come from an admin
tool whose "parent" dropdown includes the mode being edited, or from a copy
error in a data load. A self-parented mode puts a loop in any recursive
rollup query, which would never finish. `IS DISTINCT FROM` is used instead of
`<>` so that a top-level mode (`parent_mode_id` NULL) passes the check.
Longer cycles (A → B → A) cannot be caught by a row-level CHECK, because that
needs other rows. Preventing those is left to the application, together with
the other cross-row rules listed in Unit 1.

**`chk_players_display_name_not_blank` and `chk_game_modes_mode_name_not_blank`: `btrim(name) <> ''`.**
Make an empty or whitespace-only name unstorable. `NOT NULL` alone does not do
this, because `''` is a value, not a NULL. Blank names could come from a
sign-up form that submits an empty field, or from a CSV import with a missing
column. A blank display name makes a leaderboard row with no visible name. A
blank mode name is worse, because the `UNIQUE` constraint lets one mode claim
`''`, and that row then appears in every mode report as an unlabelled entry.
