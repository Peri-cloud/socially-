import os
import hashlib
import hmac
import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import psycopg
from psycopg.rows import dict_row
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request, Response, Depends
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, EmailStr, field_validator
from starlette.middleware.sessions import SessionMiddleware

load_dotenv()
BASE_DIR = Path(__file__).resolve().parent
DATABASE_URL = os.getenv("DATABASE_URL", "")
SESSION_SECRET = os.getenv("SESSION_SECRET", "")
COOKIE_SECURE = os.getenv("COOKIE_SECURE", "false").lower() == "true"

app = FastAPI(title="Socially API", version="1.0.0", description="API for the Socially PostgreSQL DBMS project")
app.add_middleware(
    SessionMiddleware,
    secret_key=SESSION_SECRET or "local-development-only-change-this-secret",
    session_cookie="socially_session",
    same_site="lax",
    https_only=COOKIE_SECURE,
    max_age=60 * 60 * 24 * 7,
)

# Same-origin deployment is recommended. This permissive CORS setting is not used for credentials;
# if you split the frontend and API into separate origins, configure an explicit trusted origin.
app.add_middleware(CORSMiddleware, allow_origins=[], allow_credentials=True, allow_methods=["GET", "POST", "DELETE"], allow_headers=["Content-Type"])


def db():
    if not DATABASE_URL:
        raise HTTPException(status_code=503, detail="DATABASE_URL is not configured. Set it in your environment.")
    try:
        with psycopg.connect(DATABASE_URL, row_factory=dict_row, connect_timeout=8) as conn:
            yield conn
    except psycopg.OperationalError as exc:
        raise HTTPException(status_code=503, detail="Cannot connect to PostgreSQL. Check DATABASE_URL and database availability.") from exc


class Credentials(BaseModel):
    username: str = Field(min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_.-]+$")
    password: str = Field(min_length=8, max_length=128)

class Registration(Credentials):
    email: EmailStr

class PostInput(BaseModel):
    content: str = Field(min_length=1, max_length=5000)
    @field_validator("content")
    @classmethod
    def content_not_blank(cls, value):
        if not value.strip():
            raise ValueError("Post content cannot be blank")
        return value.strip()

class CommentInput(BaseModel):
    comment_text: str = Field(min_length=1, max_length=2000)
    @field_validator("comment_text")
    @classmethod
    def comment_not_blank(cls, value):
        if not value.strip():
            raise ValueError("Comment text cannot be blank")
        return value.strip()


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=64)
    return f"scrypt${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    # Classroom seed.sql intentionally contains fake placeholders; they must never authenticate.
    try:
        algorithm, salt_hex, digest_hex = stored.split("$", 2)
        if algorithm != "scrypt":
            return False
        actual = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt_hex), n=2**14, r=8, p=1, dklen=64)
        return hmac.compare_digest(actual.hex(), digest_hex)
    except (ValueError, TypeError):
        return False


def current_user(request: Request, conn=Depends(db)):
    uid = request.session.get("user_id")
    if not uid:
        raise HTTPException(status_code=401, detail="Please log in to continue.")
    row = conn.execute("SELECT user_id, username, email, created_at FROM users WHERE user_id = %s", (uid,)).fetchone()
    if not row:
        request.session.clear()
        raise HTTPException(status_code=401, detail="Session is no longer valid. Please log in again.")
    return row


@app.get("/")
def dashboard():
    return FileResponse(BASE_DIR / "index.html")

@app.get("/health")
def health(conn=Depends(db)):
    conn.execute("SELECT 1")
    return {"ok": True, "database": "connected", "time": datetime.now(timezone.utc).isoformat()}

@app.post("/api/auth/register", status_code=201)
def register(payload: Registration, request: Request, conn=Depends(db)):
    username = payload.username.strip()
    email = str(payload.email).strip().lower()
    try:
        row = conn.execute(
            "INSERT INTO users (username, email, password_hash) VALUES (%s, %s, %s) RETURNING user_id, username, email, created_at",
            (username, email, hash_password(payload.password)),
        ).fetchone()
        conn.commit()
    except psycopg.errors.UniqueViolation as exc:
        conn.rollback()
        raise HTTPException(status_code=409, detail="That username or email is already registered.") from exc
    request.session.clear()
    request.session["user_id"] = row["user_id"]
    return {"user": row}

@app.post("/api/auth/login")
def login(payload: Credentials, request: Request, conn=Depends(db)):
    row = conn.execute("SELECT user_id, username, email, password_hash, created_at FROM users WHERE lower(username) = lower(%s)", (payload.username.strip(),)).fetchone()
    if not row or not verify_password(payload.password, row["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid username or password. Seed users have classroom-only fake password hashes; register a new account to sign in.")
    request.session.clear()
    request.session["user_id"] = row["user_id"]
    return {"user": {k: row[k] for k in ("user_id", "username", "email", "created_at")}}

@app.post("/api/auth/logout")
def logout(request: Request):
    request.session.clear()
    return {"ok": True}

@app.get("/api/auth/me")
def me(user=Depends(current_user)):
    return {"user": user}

@app.get("/api/stats")
def stats(user=Depends(current_user), conn=Depends(db)):
    row = conn.execute("""
        SELECT (SELECT COUNT(*) FROM users) AS users,
               (SELECT COUNT(*) FROM posts) AS posts,
               (SELECT COUNT(*) FROM likes) AS likes,
               (SELECT COUNT(*) FROM comments) AS comments
    """).fetchone()
    return row

@app.get("/api/posts")
def list_posts(user=Depends(current_user), conn=Depends(db), limit: int = 50):
    limit = max(1, min(limit, 100))
    return conn.execute("""
        SELECT p.post_id, p.user_id, u.username AS author, p.content, p.created_at,
               COUNT(DISTINCT l.like_id)::int AS like_count,
               COUNT(DISTINCT c.comment_id)::int AS comment_count,
               BOOL_OR(l.user_id = %s) AS liked_by_me
        FROM posts p JOIN users u ON u.user_id = p.user_id
        LEFT JOIN likes l ON l.post_id = p.post_id
        LEFT JOIN comments c ON c.post_id = p.post_id
        GROUP BY p.post_id, p.user_id, u.username, p.content, p.created_at
        ORDER BY p.created_at DESC, p.post_id DESC LIMIT %s
    """, (user["user_id"], limit)).fetchall()

@app.post("/api/posts", status_code=201)
def create_post(payload: PostInput, user=Depends(current_user), conn=Depends(db)):
    row = conn.execute("INSERT INTO posts (user_id, content) VALUES (%s, %s) RETURNING post_id, user_id, content, created_at", (user["user_id"], payload.content)).fetchone()
    conn.commit()
    return {**row, "author": user["username"], "like_count": 0, "comment_count": 0, "liked_by_me": False}

@app.post("/api/posts/{post_id}/like")
def toggle_like(post_id: int, user=Depends(current_user), conn=Depends(db)):
    post = conn.execute("SELECT user_id FROM posts WHERE post_id = %s", (post_id,)).fetchone()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found.")
    if post["user_id"] == user["user_id"]:
        raise HTTPException(status_code=400, detail="You cannot like your own post.")
    existing = conn.execute("SELECT like_id FROM likes WHERE user_id = %s AND post_id = %s", (user["user_id"], post_id)).fetchone()
    if existing:
        conn.execute("DELETE FROM likes WHERE like_id = %s", (existing["like_id"],))
        liked = False
    else:
        conn.execute("INSERT INTO likes (user_id, post_id) VALUES (%s, %s)", (user["user_id"], post_id))
        liked = True
    conn.commit()
    count = conn.execute("SELECT COUNT(*) AS n FROM likes WHERE post_id = %s", (post_id,)).fetchone()["n"]
    return {"post_id": post_id, "liked": liked, "like_count": count}

@app.get("/api/posts/{post_id}/comments")
def list_comments(post_id: int, user=Depends(current_user), conn=Depends(db)):
    if not conn.execute("SELECT 1 FROM posts WHERE post_id = %s", (post_id,)).fetchone():
        raise HTTPException(status_code=404, detail="Post not found.")
    return conn.execute("""SELECT c.comment_id, c.post_id, c.user_id, u.username, c.comment_text, c.created_at
        FROM comments c JOIN users u ON u.user_id = c.user_id WHERE c.post_id = %s
        ORDER BY c.created_at ASC, c.comment_id ASC""", (post_id,)).fetchall()

@app.post("/api/posts/{post_id}/comments", status_code=201)
def add_comment(post_id: int, payload: CommentInput, user=Depends(current_user), conn=Depends(db)):
    if not conn.execute("SELECT 1 FROM posts WHERE post_id = %s", (post_id,)).fetchone():
        raise HTTPException(status_code=404, detail="Post not found.")
    row = conn.execute("INSERT INTO comments (post_id, user_id, comment_text) VALUES (%s, %s, %s) RETURNING comment_id, post_id, user_id, comment_text, created_at", (post_id, user["user_id"], payload.comment_text)).fetchone()
    conn.commit()
    return {**row, "username": user["username"]}

@app.get("/api/users")
def list_users(user=Depends(current_user), conn=Depends(db)):
    return conn.execute("""SELECT u.user_id, u.username, u.email, u.created_at,
        COUNT(DISTINCT p.post_id)::int AS post_count
        FROM users u LEFT JOIN posts p ON p.user_id = u.user_id
        GROUP BY u.user_id ORDER BY u.created_at DESC, u.user_id DESC LIMIT 100""").fetchall()
