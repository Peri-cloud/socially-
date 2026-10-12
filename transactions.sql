-- =============================================================
-- transactions.sql : four worked transaction examples
-- Run schema.sql and seed.sql first, then run this file once.
-- Examples 1 and 3 COMMIT new rows; examples 2 and 4 leave the
-- seed counts unchanged (rollback / partial rollback).
--
-- ACID recap used in the comments below:
--   Atomicity  = all statements run, or none run
--   Consistency= constraints hold before and after
--   Isolation  = other sessions never see uncommitted work
--   Durability = once committed, the data survives a crash
-- =============================================================

-- ---------------------------------------------------------------
-- (1) BEGIN / COMMIT : a new post and one like saved together.
--     Atomicity: both INSERTs succeed or neither does.
--     Consistency: the FK to Users and the UNIQUE pair are checked.
--     Isolation: other sessions see nothing until COMMIT.
--     Durability: after COMMIT the rows survive a server crash.
-- ---------------------------------------------------------------
BEGIN;

    INSERT INTO Posts (user_id, content)
    VALUES (1, 'Transaction demo: this post and its first like are saved atomically.');

    -- currval() returns the ID this session just generated.
    INSERT INTO Likes (post_id, user_id)
    VALUES (currval('posts_post_id_seq'), 2);

COMMIT;

-- Verify: the new post exists and carries exactly one like.
SELECT post_id, content FROM Posts ORDER BY post_id DESC LIMIT 1;
SELECT * FROM Likes ORDER BY like_id DESC LIMIT 1;

-- ---------------------------------------------------------------
-- (2) Failed INSERT followed by ROLLBACK (duplicate like).
--     User 2 already likes post 1 in the seed data, so the UNIQUE
--     constraint uq_likes_user_post stops the second like.
--     Atomicity: the failed statement aborts the whole transaction.
--     Consistency: the UNIQUE rule blocks a double like.
--     Isolation: the doomed INSERT was never visible to anyone.
--     Durability: only committed data is written to disk.
-- ---------------------------------------------------------------
BEGIN;

    INSERT INTO Likes (post_id, user_id) VALUES (1, 2);
    -- ERROR: duplicate key value violates unique constraint
    --        "uq_likes_user_post"
    --        Detail: Key (user_id, post_id)=(2, 1) already exists.
    -- After the error PostgreSQL refuses further work in this
    -- transaction until you issue ROLLBACK.

ROLLBACK;

-- Verify: the like count is still 12 and no new row appeared.
SELECT COUNT(*) AS total_likes FROM Likes;
SELECT * FROM Likes WHERE user_id = 2 AND post_id = 1;

-- ---------------------------------------------------------------
-- (3) Post + its first comment in ONE transaction.
--     Atomicity: the comment can never exist without its post.
--     If the second INSERT failed, ROLLBACK would undo the first.
--     Consistency: both FKs and the CHECK on text are enforced.
--     Isolation: the pair appears together at COMMIT time.
--     Durability: COMMIT writes both rows durably.
-- ---------------------------------------------------------------
BEGIN;

    INSERT INTO Posts (user_id, content)
    VALUES (5, 'My first post - published together with its first comment.');

    INSERT INTO Comments (post_id, user_id, comment_text)
    VALUES (currval('posts_post_id_seq'), 5, 'First!');

COMMIT;

-- Verify: the newest post shows together with its comment.
SELECT p.post_id, p.content, c.comment_text
FROM Posts p
JOIN Comments c ON c.post_id = p.post_id
ORDER BY p.post_id DESC
LIMIT 1;

-- ---------------------------------------------------------------
-- (4) SAVEPOINT and ROLLBACK TO : undo part of a transaction.
--     A SAVEPOINT is a named marker. ROLLBACK TO undoes only the
--     work done after the marker; the outer transaction survives.
--     Atomicity: the outer transaction still commits as one unit.
--     Consistency: the CHECK on comment_text rejects empty text.
--     Isolation: the undone bad row was never visible to others.
--     Durability: only the surviving rows become permanent.
-- ---------------------------------------------------------------
BEGIN;

    INSERT INTO Comments (post_id, user_id, comment_text)
    VALUES (1, 4, 'This good comment will survive.');

    SAVEPOINT before_bad_row;

    INSERT INTO Comments (post_id, user_id, comment_text)
    VALUES (1, 4, '   ');
    -- ERROR: new row for relation "comments" violates check
    --        constraint "comments_comment_text_check"

    ROLLBACK TO before_bad_row;   -- undo ONLY the bad insert

    INSERT INTO Comments (post_id, user_id, comment_text)
    VALUES (1, 4, 'Fixed comment - saved instead of the bad one.');

COMMIT;

-- Verify: the two good comments exist, the empty one does not.
SELECT comment_id, comment_text
FROM Comments
WHERE post_id = 1 AND user_id = 4
ORDER BY comment_id;
