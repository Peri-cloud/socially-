-- =============================================================
-- queries.sql : demonstration queries for the project report
-- Run schema.sql and seed.sql first.
-- Each query has a one-line purpose; the expected output shown in
-- the comments is derived from the seed data (5 users, 8 posts,
-- 10 comments, 12 likes) and is reproduced in the project notes.
-- =============================================================

-- (1) INNER JOIN - show every post together with its author's name.
SELECT p.post_id, u.username AS author, p.content, p.created_at
FROM Posts p
JOIN Users u ON u.user_id = p.user_id
ORDER BY p.post_id;
-- Expected: 8 rows. Authors in order: aarav_sharma, priya_verma,
-- rohan_mehta, aarav_sharma, sneha_reddy, vikram_singh, priya_verma, sneha_reddy.

-- (2) LEFT JOIN + COUNT - all users with their comment counts,
--     including users with zero comments (LEFT JOIN keeps them).
SELECT u.user_id, u.username, COUNT(c.comment_id) AS comments_made
FROM Users u
LEFT JOIN Comments c ON c.user_id = u.user_id
GROUP BY u.user_id, u.username
ORDER BY comments_made DESC, u.username;
-- Expected: priya_verma 4, aarav_sharma 2, rohan_mehta 2,
--           sneha_reddy 2, vikram_singh 0.

-- (3) GROUP BY / HAVING - users who posted more than once.
--     WHERE filters rows before grouping; HAVING filters groups.
SELECT u.user_id, u.username, COUNT(p.post_id) AS posts_written
FROM Users u
JOIN Posts p ON p.user_id = u.user_id
GROUP BY u.user_id, u.username
HAVING COUNT(p.post_id) > 1
ORDER BY posts_written DESC, u.username;
-- Expected: aarav_sharma 2, priya_verma 2, sneha_reddy 2.

-- (4) Subquery with IN - posts that priya (user 2) commented on.
SELECT p.post_id, p.content
FROM Posts p
WHERE p.post_id IN (
    SELECT c.post_id FROM Comments c WHERE c.user_id = 2
)
ORDER BY p.post_id;
-- Expected: posts 1, 3, 4 and 8.

-- (5) Subquery with HAVING - posts with more likes than the
--     average post. Average = 12 likes / 8 posts = 1.5.
SELECT p.post_id, u.username AS author, COUNT(l.like_id) AS like_count
FROM Posts p
JOIN Users u     ON u.user_id = p.user_id
LEFT JOIN Likes l ON l.post_id = p.post_id
GROUP BY p.post_id, u.username
HAVING COUNT(l.like_id) > (
    SELECT COUNT(*)::NUMERIC / (SELECT COUNT(*) FROM Posts)
    FROM Likes
)
ORDER BY like_count DESC, p.post_id;
-- Expected: post 1 (3 likes, aarav_sharma), post 2 (3 likes, priya_verma).

-- (6) ORDER BY / LIMIT - the 3 most recent posts with authors.
SELECT p.post_id, u.username AS author, p.content, p.created_at
FROM Posts p
JOIN Users u ON u.user_id = p.user_id
ORDER BY p.created_at DESC
LIMIT 3;
-- Expected: posts 8 (sneha_reddy), 7 (priya_verma), 6 (vikram_singh).

-- (7) LEFT JOIN ... IS NULL (anti-join) - users who never commented.
SELECT u.user_id, u.username
FROM Users u
LEFT JOIN Comments c ON c.user_id = u.user_id
WHERE c.comment_id IS NULL;
-- Expected: vikram_singh (user_id 5).
