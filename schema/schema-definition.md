# Schema Definition (Task 1.1)

Relation schemas for the Game Telemetry database. For each relation: its
attributes, the domain (type) of each, and the primary key.

## players
| Attribute | Domain | |
|-----------|--------|--|
| player_id | INTEGER | primary key, auto-generated |
| display_name | VARCHAR(50), NOT NULL | |
| created_at | TIMESTAMPTZ, NOT NULL | |

Primary key: player_id

## matches
| Attribute | Domain | |
|-----------|--------|--|
| match_id | BIGINT | primary key, auto-generated |
| match_label | VARCHAR(100), NOT NULL | |
| is_active | BOOLEAN, NOT NULL | true = live, false = completed |
| duration_sec | INTEGER, nullable | NULL while active; >= 0 once completed |
| started_at | TIMESTAMPTZ, NOT NULL | |

Primary key: match_id

## game_modes
| Attribute | Domain | |
|-----------|--------|--|
| game_mode_id | SMALLINT | primary key, auto-generated |
| mode_name | VARCHAR(50), NOT NULL, UNIQUE | |

Primary key: game_mode_id

## match_modes
| Attribute | Domain | |
|-----------|--------|--|
| match_id | BIGINT, NOT NULL | foreign key -> matches |
| game_mode_id | SMALLINT, NOT NULL | foreign key -> game_modes |

Primary key: composite (match_id, game_mode_id)

## match_participants
| Attribute | Domain | |
|-----------|--------|--|
| match_id | BIGINT, NOT NULL | foreign key -> matches |
| player_id | INTEGER, NOT NULL | foreign key -> players |
| score | INTEGER, NOT NULL | the metric aggregated in later units; >= 0 |
| played_at | TIMESTAMPTZ, NOT NULL | timestamp of the result |

Primary key: composite (match_id, player_id)