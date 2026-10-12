-- =============================================================
-- seed.sql : small, consistent sample data set
-- 5 users, 8 posts, 10 comments, 12 likes.
-- Run AFTER schema.sql. All IDs are explicit, so every foreign
-- key points to a row that really exists.
--
-- IMPORTANT: the password_hash values are FAKE placeholders made
-- for classroom use only. Real systems must store a salted hash
-- (for example bcrypt) and never the plaintext password.
--
-- Re-run note: this file assumes the tables are empty (fresh
-- schema.sql). Running it twice would duplicate usernames/emails.
-- =============================================================

BEGIN;

-- ------------------------------------------------------- 5 users
INSERT INTO Users (user_id, username, email, password_hash, created_at) VALUES
(1, 'aarav_sharma', 'aarav@example.com',  'FAKE-HASH-001-do-not-use', '2025-01-05 09:00:00'),
(2, 'priya_verma',  'priya@example.com',  'FAKE-HASH-002-do-not-use', '2025-01-06 10:15:00'),
(3, 'rohan_mehta',  'rohan@example.com',  'FAKE-HASH-003-do-not-use', '2025-01-08 14:30:00'),
(4, 'sneha_reddy',  'sneha@example.com',  'FAKE-HASH-004-do-not-use', '2025-01-10 11:45:00'),
(5, 'vikram_singh', 'vikram@example.com', 'FAKE-HASH-005-do-not-use', '2025-01-12 16:20:00');

-- ------------------------------------------------------- 8 posts
INSERT INTO Posts (post_id, user_id, content, created_at) VALUES
(1, 1, 'Excited to share that our final year DBMS project is underway! #Socially', '2025-02-01 09:00:00'),
(2, 2, 'Just finished learning joins in PostgreSQL. GROUP BY is powerful!',        '2025-02-01 10:30:00'),
(3, 3, 'Our team is building a social media dashboard this semester.',             '2025-02-02 11:15:00'),
(4, 1, 'Hot tip: always back up your database before running migrations.',         '2025-02-03 08:45:00'),
(5, 4, 'Loving the new UI of our Socially dashboard prototype!',                   '2025-02-04 12:00:00'),
(6, 5, 'Can someone explain normalization in simple words?',                       '2025-02-05 14:20:00'),
(7, 2, 'ACID properties make transactions reliable. More on this soon!',           '2025-02-06 16:05:00'),
(8, 4, 'PostgreSQL triggers are surprisingly easy to write.',                      '2025-02-07 18:30:00');

-- ---------------------------------------------------- 10 comments
INSERT INTO Comments (comment_id, post_id, user_id, comment_text, created_at) VALUES
(1,  1, 2, 'All the best, Aarav!',                  '2025-02-01 09:30:00'),
(2,  1, 3, 'Looking forward to the demo.',          '2025-02-01 11:00:00'),
(3,  2, 1, 'Try HAVING next - it filters groups.',  '2025-02-01 12:00:00'),
(4,  3, 2, 'Can I join your team?',                 '2025-02-02 15:40:00'),
(5,  3, 4, 'Count me in for testing.',              '2025-02-02 16:10:00'),
(6,  4, 2, 'Saved me once. Great advice.',          '2025-02-03 10:05:00'),
(7,  5, 1, 'The charts look clean.',                '2025-02-04 13:25:00'),
(8,  6, 3, 'Think 1NF, 2NF, 3NF step by step.',     '2025-02-05 15:00:00'),
(9,  7, 4, 'Atomicity is my favourite property.',   '2025-02-06 17:00:00'),
(10, 8, 2, 'Please share an example trigger.',      '2025-02-07 19:15:00');

-- ------------------------------------------------------ 12 likes
-- Every (user_id, post_id) pair is unique, and nobody likes their
-- own post, so the data stays valid even after the self-like
-- trigger from plpgsql.sql is created.
INSERT INTO Likes (like_id, post_id, user_id, created_at) VALUES
(1,  2, 1, '2025-02-01 13:00:00'),  -- aarav  likes post 2
(2,  3, 1, '2025-02-02 09:00:00'),  -- aarav  likes post 3
(3,  5, 1, '2025-02-04 12:30:00'),  -- aarav  likes post 5
(4,  1, 2, '2025-02-01 09:15:00'),  -- priya  likes post 1
(5,  4, 2, '2025-02-03 09:00:00'),  -- priya  likes post 4
(6,  7, 2, '2025-02-06 16:10:00'),  -- priya  likes post 7
(7,  1, 3, '2025-02-01 10:00:00'),  -- rohan  likes post 1
(8,  2, 3, '2025-02-01 14:00:00'),  -- rohan  likes post 2
(9,  6, 3, '2025-02-05 15:30:00'),  -- rohan  likes post 6
(10, 1, 4, '2025-02-04 12:45:00'),  -- sneha  likes post 1
(11, 8, 4, '2025-02-07 19:00:00'),  -- sneha  likes post 8
(12, 2, 5, '2025-02-01 15:00:00');  -- vikram likes post 2

COMMIT;

-- Resume auto-generated IDs after the largest explicit ID, so the
-- next INSERT gets 6 / 9 / 11 / 13 instead of colliding.
SELECT setval('users_user_id_seq',       (SELECT MAX(user_id)    FROM Users));
SELECT setval('posts_post_id_seq',       (SELECT MAX(post_id)    FROM Posts));
SELECT setval('comments_comment_id_seq', (SELECT MAX(comment_id) FROM Comments));
SELECT setval('likes_like_id_seq',       (SELECT MAX(like_id)    FROM Likes));
