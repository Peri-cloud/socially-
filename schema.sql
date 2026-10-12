-- =============================================================
-- Socially - Social Media Interaction and Management System
-- schema.sql : tables, constraints and indexes
-- Target  : PostgreSQL 14 or later
-- Run this file FIRST (it drops and recreates the four tables).
--
-- Note for viva: the procedural language of PostgreSQL is PL/pgSQL,
-- the equivalent of Oracle's PL/SQL. It is used in plpgsql.sql.
-- =============================================================

-- Drop in reverse dependency order so this file can be re-run safely.
DROP TABLE IF EXISTS Likes    CASCADE;
DROP TABLE IF EXISTS Comments CASCADE;
DROP TABLE IF EXISTS Posts    CASCADE;
DROP TABLE IF EXISTS Users    CASCADE;

-- -------------------------------------------------------------
-- 1) USERS : one row per registered account.
--    username and email are candidate keys, so both are UNIQUE.
--    password_hash stores a HASH, never the plaintext password.
-- -------------------------------------------------------------
CREATE TABLE Users (
    user_id       SERIAL       PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    email         VARCHAR(120) NOT NULL UNIQUE
                               CHECK (email LIKE '%_@_%._%'),
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------
-- 2) POSTS : one row per published post.
--    ON DELETE CASCADE is justified: a post cannot exist without
--    its author, so deleting a user removes the user's posts too.
--    CHECK rejects posts that are empty or only spaces.
-- -------------------------------------------------------------
CREATE TABLE Posts (
    post_id    SERIAL    PRIMARY KEY,
    user_id    INTEGER   NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    content    TEXT      NOT NULL CHECK (LENGTH(TRIM(content)) > 0),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------
-- 3) COMMENTS : one row per comment on a post.
--    Two foreign keys keep both the post and the author valid.
--    Deleting a post or a user cascades, so no orphan rows remain.
-- -------------------------------------------------------------
CREATE TABLE Comments (
    comment_id   SERIAL    PRIMARY KEY,
    post_id      INTEGER   NOT NULL REFERENCES Posts(post_id) ON DELETE CASCADE,
    user_id      INTEGER   NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    comment_text TEXT      NOT NULL CHECK (LENGTH(TRIM(comment_text)) > 0),
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------
-- 4) LIKES : one row per like.
--    UNIQUE (user_id, post_id) guarantees a user can like a given
--    post at most once. This pair is a candidate key besides like_id.
-- -------------------------------------------------------------
CREATE TABLE Likes (
    like_id    SERIAL    PRIMARY KEY,
    post_id    INTEGER   NOT NULL REFERENCES Posts(post_id) ON DELETE CASCADE,
    user_id    INTEGER   NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_likes_user_post UNIQUE (user_id, post_id)
);

-- -------------------------------------------------------------
-- Indexes: every foreign key column is indexed, plus the columns
-- we filter or sort by most often.
-- The UNIQUE constraint above already creates an index on
-- (user_id, post_id); it serves "all likes of user X" and the
-- duplicate check. idx_likes_post_id serves per-post like counts.
-- -------------------------------------------------------------
CREATE INDEX idx_posts_user_id     ON Posts (user_id);
CREATE INDEX idx_posts_created_at  ON Posts (created_at);
CREATE INDEX idx_comments_post_id  ON Comments (post_id);
CREATE INDEX idx_comments_user_id  ON Comments (user_id);
CREATE INDEX idx_likes_post_id     ON Likes (post_id);
