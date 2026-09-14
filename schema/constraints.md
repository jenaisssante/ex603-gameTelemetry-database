# Integrity Constraints (Task 1.3)

The constraints that keep the data valid, grouped by kind. Each foreign key
states its ON DELETE behaviour and why.

The guiding principle: a match owns its own facts. The participation rows and the
mode tags recorded against a match have no meaning without it, so they are deleted
with it. Players and game modes are independent reference entities that exist on
their own, so they cannot be deleted while facts still point at them.

## Primary keys
| Relation | Primary key | Reason |
|----------|-------------|--------|
| players | player_id | Surrogate key; display names are not unique. |
| matches | match_id | Surrogate key. |
| game_modes | game_mode_id | Surrogate key. |
| match_modes | (match_id, game_mode_id) | Composite; makes a duplicate match–mode pairing impossible. |
| match_participants | (match_id, player_id) | Composite; enforces one result row per player per match. |

## Foreign keys and ON DELETE
| Child column | References | ON DELETE | Reason |
|--------------|-----------|-----------|--------|
| match_participants.match_id | matches.match_id | CASCADE | A result belongs to its match; if the match is deleted the result is meaningless and goes with it. |
| match_participants.player_id | players.player_id | RESTRICT | A player with recorded results cannot be deleted, as that would silently change historical aggregates. Account removal is handled by anonymising the player row instead. |
| match_modes.match_id | matches.match_id | CASCADE | A mode tag belongs to its match and is removed with it. |
| match_modes.game_mode_id | game_modes.game_mode_id | RESTRICT | Game modes are reference data; a mode still classifying matches must not be deletable. |

## NOT NULL
Every attribute is NOT NULL except matches.duration_sec, which is null while a
match is active and set once it completes. All primary-key and foreign-key
columns are NOT NULL by definition.

## UNIQUE
game_modes.mode_name is UNIQUE — two modes must not share a name.

## CHECK
| Relation | Constraint | Reason |
|----------|-----------|--------|
| match_participants | score >= 0 | A negative score is invalid in this model. |
| matches | duration_sec IS NULL OR duration_sec >= 0 | A duration, when present, cannot be negative. |
| matches | (is_active = true AND duration_sec IS NULL) OR (is_active = false AND duration_sec IS NOT NULL) | A live match has no final duration; a completed match must have one. This makes contradictory states impossible to store. |

## Rules left to the application
Some rules cannot be expressed as declarative constraints and are enforced in
application logic: that played_at falls within the match's active window (a
cross-table rule), that a completed match has a minimum number of participants (a
child-count rule), and how a score is computed (game logic).