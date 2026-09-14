# Unit 1 — Modelling Justification and Reflection (Task 1.4)

## Modelling justification

This schema models a game-telemetry platform around five relations: players
(actor), matches (producer), match_participants (event), game_modes (catalog),
and match_modes (junction). My design turns on three sets of decisions: primary
keys, deletion behaviour, and which rules I enforced in the schema versus the
application.

For primary keys, I gave players, matches, and game_modes a surrogate identity
key rather than a natural one. Display names and mode names are human-facing
labels that can change or collide, so identity should not depend on them, and a
surrogate keeps foreign keys narrow and stable. I also sized each key to its
scale: game_mode_id is SMALLINT because the set of modes is small and stable,
match_id is BIGINT because match volume grows without bound, and player_id is
INTEGER. The two link tables use composite keys instead. match_modes is keyed on
(match_id, game_mode_id) so a match cannot be tagged with the same mode twice.
match_participants is keyed on (match_id, player_id); this is the most important
key choice, because it puts the rule that a player has exactly one result per
match directly into the primary key rather than trusting the application to
prevent duplicates.

Every foreign key's ON DELETE rule follows one principle: a match owns its own
facts. A participation row and a mode tag mean nothing without the match they
describe, so match_participants.match_id and match_modes.match_id both CASCADE —
deleting a match removes its results and tags together. In contrast, players and
game_modes are independent reference entities, so the foreign keys pointing at
them use RESTRICT. A player or mode still referenced by existing facts cannot be
deleted, which stops a delete from silently rewriting historical aggregates.
Because player_id is part of a composite primary key, SET NULL is not available,
so RESTRICT is the correct conservative default, and account removal is handled
by anonymising the player row rather than cascading away their history.

For the schema-versus-application split, I enforced in the schema every rule that
can be written declaratively and that protects structural integrity: identity
(primary keys), referential integrity (foreign keys with explicit ON DELETE),
mandatory fields (NOT NULL), domain limits (score >= 0, duration >= 0),
uniqueness of mode names, and a CHECK tying is_active to duration_sec so a live
match has no final duration and a completed one must. That last constraint pushes
a state-machine rule into the schema, making contradictory rows impossible to
store. I left to the application the rules a table constraint cannot express: that
played_at falls inside a match's active window (a cross-table temporal rule), that
a completed match has a minimum number of participants (a child-count rule), and
how a score is computed (game logic). Drawing the line this way lets the database
guarantee that stored data is always structurally valid, while the application
owns the behavioural rules a relational schema cannot capture.

## Reflection

The decision most open to reasonable disagreement is the primary key of
match_participants. I keyed it on (match_id, player_id), which asserts that a
player produces exactly one scored result per match. A different designer could
add a surrogate participation_id and allow several rows per player per match —
reasonable if a match contains multiple rounds or scoring events that each deserve
their own timestamped row.

I chose the composite key because of how the platform is read and written. The
dominant reads are aggregations: average score per player, totals per mode,
leaderboards over time. A composite key on (match_id, player_id) gives those
queries an already-unique grain and a natural index for joins from matches and
players, with no risk of double-counting a player within a match. On the write
side, results arrive once per player when a match finalises, so the one-row-per-
player-per-match assumption matches how the data is actually produced, and the key
doubles as a guard against a retried write inserting a duplicate.

The trade-off is flexibility: if the product later records per-round telemetry,
this key forces a schema change. I judged that acceptable, because it keeps the
current model's grain clean and its integrity strong, which is what the analytical
workload needs most. Finer-grained data, if it comes, belongs in a separate event
table rather than in loosening this one.