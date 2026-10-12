-- =============================================================
-- plpgsql.sql : stored objects written in PL/pgSQL
-- PL/pgSQL is PostgreSQL's procedural language - the equivalent
-- of Oracle's PL/SQL. It adds variables, IF/ELSE, loops and
-- exception handling to plain SQL.
--
-- Function vs procedure (viva favourite):
--   FUNCTION : returns a value  -> call with  SELECT * FROM f(...);
--   PROCEDURE: returns nothing  -> call with  CALL p(...);
--   Only procedures can manage transactions (COMMIT/ROLLBACK) inside.
--
-- Run schema.sql and seed.sql first. Every object below has a
-- test call right after it, with the expected result in a comment.
-- =============================================================

-- ---------------------------------------------------------------
-- 1) toggle_like(p_user_id, p_post_id) : like / unlike switch.
--    Adds the like if missing, removes it if present.
--    Returns a short status text.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION toggle_like(p_user_id INTEGER, p_post_id INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_author INTEGER;
BEGIN
    -- Does the post exist?
    SELECT user_id INTO v_author FROM Posts WHERE post_id = p_post_id;
    IF v_author IS NULL THEN
        RETURN 'Post not found.';
    END IF;

    -- Same rule as the trigger below, but as a friendly message
    -- instead of an error.
    IF v_author = p_user_id THEN
        RETURN 'You cannot like your own post.';
    END IF;

    IF EXISTS (SELECT 1 FROM Likes
               WHERE user_id = p_user_id AND post_id = p_post_id) THEN
        DELETE FROM Likes
        WHERE user_id = p_user_id AND post_id = p_post_id;
        RETURN 'Like removed.';
    ELSE
        INSERT INTO Likes (user_id, post_id)
        VALUES (p_user_id, p_post_id);
        RETURN 'Post liked.';
    END IF;
END;
$$;

-- Test calls (expected results assume a fresh seed):
SELECT toggle_like(4, 2);    -- expect 'Post liked.'   (pair 4,2 is new)
SELECT toggle_like(4, 2);    -- expect 'Like removed.' (pair 4,2 now exists)
SELECT toggle_like(1, 1);    -- expect 'You cannot like your own post.'
SELECT toggle_like(1, 999);  -- expect 'Post not found.'
SELECT COUNT(*) AS likes_after_toggle_tests FROM Likes;  -- expect 12 (net change zero)

-- ---------------------------------------------------------------
-- 2) add_comment(p_post_id, p_user_id, p_text) : PROCEDURE.
--    Called with CALL. Handles two error types gracefully:
--      foreign_key_violation (bad post or user id)
--      check_violation       (empty comment text)
--    instead of letting the CALL crash with a raw error.
-- ---------------------------------------------------------------
CREATE OR REPLACE PROCEDURE add_comment(p_post_id INTEGER, p_user_id INTEGER, p_text TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Guard against NULL and blank text before touching the table.
    IF p_text IS NULL OR LENGTH(TRIM(p_text)) = 0 THEN
        RAISE EXCEPTION 'Comment text cannot be empty'
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO Comments (post_id, user_id, comment_text)
    VALUES (p_post_id, p_user_id, p_text);

    RAISE NOTICE 'Comment added to post % by user %.', p_post_id, p_user_id;

EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'ERROR: post % or user % does not exist.', p_post_id, p_user_id;
    WHEN check_violation THEN
        RAISE NOTICE 'ERROR: comment text cannot be empty.';
END;
$$;

-- Test calls (NOTICE output appears in the Messages tab of pgAdmin):
CALL add_comment(1, 5, 'Great project update!');   -- NOTICE: Comment added to post 1...
CALL add_comment(999, 1, 'This will fail.');       -- NOTICE: ERROR: post 999 or user 1 does not exist.
CALL add_comment(1, 999, 'Bad user here.');        -- NOTICE: ERROR: post 1 or user 999 does not exist.
CALL add_comment(1, 1, '   ');                     -- NOTICE: ERROR: comment text cannot be empty.

-- ---------------------------------------------------------------
-- 3) post_stats(p_post_id) : returns like and comment counts.
--    Call with SELECT because it is a FUNCTION.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION post_stats(p_post_id INTEGER)
RETURNS TABLE (like_count BIGINT, comment_count BIGINT)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Posts WHERE post_id = p_post_id) THEN
        RAISE EXCEPTION 'Post % does not exist.', p_post_id;
    END IF;

    RETURN QUERY
    SELECT (SELECT COUNT(*) FROM Likes    WHERE post_id = p_post_id),
           (SELECT COUNT(*) FROM Comments WHERE post_id = p_post_id);
END;
$$;

-- Test calls (these posts are not touched by the add_comment tests,
-- so the numbers stay the same even after running them):
SELECT * FROM post_stats(3);   -- expect like_count 1, comment_count 2
SELECT * FROM post_stats(8);   -- expect like_count 1, comment_count 1
SELECT * FROM post_stats(999); -- expect ERROR: Post 999 does not exist.

-- ---------------------------------------------------------------
-- 4) BEFORE INSERT trigger on Likes: block liking your own post.
--    A trigger function RETURNS TRIGGER. In a BEFORE INSERT
--    row-level trigger, returning NEW keeps the insert; raising
--    an exception aborts it with a clear message.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION block_self_like()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_author INTEGER;
BEGIN
    SELECT user_id INTO v_author FROM Posts WHERE post_id = NEW.post_id;

    IF v_author IS NOT NULL AND v_author = NEW.user_id THEN
        RAISE EXCEPTION 'Users cannot like their own post (%).', NEW.post_id
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;   -- allow the insert
END;
$$;

CREATE TRIGGER trg_block_self_like
BEFORE INSERT ON Likes
FOR EACH ROW
EXECUTE FUNCTION block_self_like();

-- Test call - expect ERROR: Users cannot like their own post (2).
-- (User 2 is the author of post 2.)
INSERT INTO Likes (post_id, user_id) VALUES (2, 2);

-- ---------------------------------------------------------------
-- 5) View: top 5 most-liked posts with author names.
--    A view is a stored query that behaves like a virtual table;
--    it always shows fresh results when selected.
--    Tie-break: oldest post first when like counts are equal.
-- ---------------------------------------------------------------
CREATE OR REPLACE VIEW top_liked_posts AS
SELECT p.post_id,
       u.username  AS author,
       p.content,
       COUNT(l.like_id) AS like_count
FROM Posts p
JOIN Users u      ON u.user_id = p.user_id
LEFT JOIN Likes l ON l.post_id = p.post_id
GROUP BY p.post_id, u.username, p.content
ORDER BY like_count DESC, p.created_at ASC
LIMIT 5;

-- Test call (expected output from the seed data):
SELECT * FROM top_liked_posts;
-- post_id |   author     | like_count
--       1 | aarav_sharma |          3
--       2 | priya_verma  |          3
--       3 | rohan_mehta  |          1
--       4 | aarav_sharma |          1
--       5 | sneha_reddy  |          1
