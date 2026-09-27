-- =================================================================
-- EX 603 Assignment 2 — schema.sql
-- Theme:  Game Telemetry (Theme 3)
-- Author: Andrew Boban
-- Target: PostgreSQL 14+
-- =================================================================
-- Creation order (a table is created only after every table it references):
--
--   Table                Outgoing references
--   -------------------  -----------------------------------------
--   1. players           (none)
--   2. game_modes        game_modes (itself — parent mode)
--   3. matches           (none)
--   4. match_modes       matches, game_modes
--   5. match_participants matches, players
--
-- players, game_modes and matches have no outgoing references to other
-- tables, so they come first; the two tables that hold foreign keys to them
-- come last. The drop block below runs in exactly the reverse order.
-- =================================================================

-- Reset. Reverse creation order, so no dependency blocks a drop.
DROP TABLE IF EXISTS match_participants CASCADE;
DROP TABLE IF EXISTS match_modes        CASCADE;
DROP TABLE IF EXISTS matches            CASCADE;
DROP TABLE IF EXISTS game_modes         CASCADE;
DROP TABLE IF EXISTS players            CASCADE;


-- ----------------------------------------------------------------
-- 1. players — first, because it references nothing.
--    The actor: every scored result points back to one player.
-- ----------------------------------------------------------------
CREATE TABLE players (
    player_id    INTEGER     GENERATED ALWAYS AS IDENTITY,
    display_name VARCHAR(50) NOT NULL,
    created_at   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_players PRIMARY KEY (player_id),
    CONSTRAINT chk_players_display_name_not_blank
        CHECK (btrim(display_name) <> '')
);


-- ----------------------------------------------------------------
-- 2. game_modes — second, because its only reference is to itself.
--    Catalog of modes. The recursive FK lives here: a mode may sit
--    under a parent mode family (e.g. 'Ranked Solo' under 'Ranked'),
--    so mode usage can be rolled up by family in later queries.
--    Top-level modes have parent_mode_id = NULL.
-- ----------------------------------------------------------------
CREATE TABLE game_modes (
    game_mode_id   INTEGER     GENERATED ALWAYS AS IDENTITY,
    mode_name      VARCHAR(50) NOT NULL,
    parent_mode_id INTEGER,
    CONSTRAINT pk_game_modes PRIMARY KEY (game_mode_id),
    CONSTRAINT uq_game_modes_mode_name UNIQUE (mode_name),
    CONSTRAINT fk_game_modes_parent
        FOREIGN KEY (parent_mode_id) REFERENCES game_modes (game_mode_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_game_modes_no_self_parent
        CHECK (parent_mode_id IS DISTINCT FROM game_mode_id),
    CONSTRAINT chk_game_modes_mode_name_not_blank
        CHECK (btrim(mode_name) <> '')
);


-- ----------------------------------------------------------------
-- 3. matches — third, because it references nothing.
--    The producer: each match owns its participation rows and its
--    mode tags. duration_sec is NULL while the match is live and set
--    when it completes; the CHECKs below tie the two together.
-- ----------------------------------------------------------------
CREATE TABLE matches (
    match_id     INTEGER      GENERATED ALWAYS AS IDENTITY,
    match_label  VARCHAR(100) NOT NULL,
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
    duration_sec INTEGER,
    started_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_matches PRIMARY KEY (match_id),
    CONSTRAINT chk_matches_duration_nonnegative
        CHECK (duration_sec IS NULL OR duration_sec >= 0),
    CONSTRAINT chk_matches_active_duration_consistent
        CHECK (   (is_active = TRUE  AND duration_sec IS NULL)
               OR (is_active = FALSE AND duration_sec IS NOT NULL))
);


-- ----------------------------------------------------------------
-- 4. match_modes — after matches and game_modes, which it joins.
--    Junction resolving the M:N between matches and game_modes.
--    The primary key is the pair of foreign keys, not a new id.
-- ----------------------------------------------------------------
CREATE TABLE match_modes (
    match_id     INTEGER NOT NULL,
    game_mode_id INTEGER NOT NULL,
    CONSTRAINT pk_match_modes PRIMARY KEY (match_id, game_mode_id),
    CONSTRAINT fk_match_modes_match
        FOREIGN KEY (match_id) REFERENCES matches (match_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_match_modes_game_mode
        FOREIGN KEY (game_mode_id) REFERENCES game_modes (game_mode_id)
        ON DELETE RESTRICT
);


-- ----------------------------------------------------------------
-- 5. match_participants — last, after matches and players.
--    The event / fact table: one scored result per player per match.
--    The composite key makes a second result for the same player in
--    the same match unstorable. score is the metric for later units.
-- ----------------------------------------------------------------
CREATE TABLE match_participants (
    match_id  INTEGER   NOT NULL,
    player_id INTEGER   NOT NULL,
    score     INTEGER   NOT NULL,
    played_at TIMESTAMP NOT NULL,
    CONSTRAINT pk_match_participants PRIMARY KEY (match_id, player_id),
    CONSTRAINT fk_match_participants_match
        FOREIGN KEY (match_id) REFERENCES matches (match_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_match_participants_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_match_participants_score_nonnegative
        CHECK (score >= 0)
);

-- Derived values: none stored. A match's end time (started_at +
-- duration_sec) and every per-player / per-mode aggregate are computed
-- at query time. See analysis/unit2.md for the reasoning.
