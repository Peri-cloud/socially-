# Socially — PostgreSQL-connected dashboard

This package preserves the original `social_media_dashboard.html` design (renamed to `index.html`) and connects it to a FastAPI backend and the project's existing PostgreSQL schema.

## What is connected

- Login and account registration (accounts are stored in `Users`).
- Live dashboard counts for users, posts, likes and comments.
- Recent posts from PostgreSQL; create post; toggle like/unlike; list and add comments.
- Community member table and CSV export of live metrics/posts.
- HTTP-only signed session cookie; passwords for newly registered accounts are stored as salted scrypt hashes.
- The app is served by FastAPI at `/`, so frontend and API are same-origin; no browser-side database password is exposed.

## Important project-specific facts

1. `schema.sql` drops and recreates the four tables. Run it only against a disposable/new project database; it destroys existing project data.
2. Run `seed.sql` once after the schema. It contains 5 users, 8 posts, 10 comments and 12 likes.
3. Seed `password_hash` values are deliberately fake classroom placeholders. Those five seeded users cannot log in. Register a new account in the dashboard to test authentication.
4. The database design does not have a category, role, profile, share, or notification table. The dashboard therefore does not pretend those features are persisted.
5. The `add user` action directs users to account registration rather than letting every signed-in account create arbitrary accounts.

## Local setup (Windows 11 / PowerShell)

### 1. Prepare PostgreSQL

Install/run PostgreSQL 14+ and pgAdmin. Create a new empty database, for example `socially`.

In pgAdmin's Query Tool connected to `socially`, run these in order:

1. `schema.sql`
2. `seed.sql` (once only)
3. `queries.sql` (read-only examples; optional)
4. `plpgsql.sql` statement by statement if you want the project's functions, procedure, trigger and view. It includes a deliberately failing self-like test at the end; expect that error.
5. `transactions.sql` only when you want to demonstrate the transaction examples. It intentionally causes errors and changes the seed row counts; do not run it when you need the exact original seed counts for screenshots.

The API uses the tables and constraints in `schema.sql`. It does not require the PL/pgSQL objects because the API implements its actions using parameterized SQL and the same database rules.

### 2. Configure Python

Python 3.11+ recommended. In PowerShell, from this folder:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```

Edit `.env` and set `DATABASE_URL` to your PostgreSQL credentials. Example (replace the password):

```env
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/socially
SESSION_SECRET=put-a-long-random-secret-here-at-least-32-characters
COOKIE_SECURE=false
```

Keep `.env` private and never commit it. For a real secret, generate one with `py -c "import secrets; print(secrets.token_urlsafe(48))"`.

### 3. Run

```powershell
uvicorn main:app --reload
```

Open `http://127.0.0.1:8000`. Use **Create an account** to register, then create a post, like another user's post, and add comments. The `/health` endpoint reports whether PostgreSQL is reachable; `/docs` shows the API documentation.

## Deployment

This app is a Python web service, not a static-only Vercel site. Deploy the folder to a Python host such as Render or Railway and attach a managed PostgreSQL database. Configure these environment variables on the host:

- `DATABASE_URL`: provider's PostgreSQL URL
- `SESSION_SECRET`: long random secret
- `COOKIE_SECURE=true`: required for HTTPS production

Build/install command: `pip install -r requirements.txt`

Start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`

Before deployment, run `schema.sql` and `seed.sql` against the intended database. Do not publish `.env`, database credentials, or a database URL in frontend JavaScript. If you later choose Vercel for the static frontend, keep the API and PostgreSQL connection on a separate backend service and configure explicit CORS and an API base URL; do not connect a browser directly to PostgreSQL.

## Security / scope notes

- This is a classroom/demo implementation. Before public production use, add login rate limiting, email verification, password reset, moderation, and stronger operational monitoring.
- The session cookie is HttpOnly and SameSite=Lax. HTTPS deployments must set `COOKIE_SECURE=true`.
- Current endpoints require a valid session for application data. Registration is open; if a private community is required, add an invitation/admin approval policy.
- The UI escapes user-provided text before rendering it, and SQL uses parameterized queries.

## Database tables

`Users`, `Posts`, `Comments`, `Likes` — exactly as in the supplied schema. No extra application tables or unverified project claims were added.
