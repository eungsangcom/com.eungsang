"""List public tables on the NAS Postgres (local helper)."""

import os

import psycopg2

conn = psycopg2.connect(
    host=os.getenv("PGHOST", "192.168.0.72"),
    port=int(os.getenv("PGPORT", "5433")),
    user=os.getenv("PGUSER", "eungsang"),
    password=os.environ["PGPASSWORD"],
    dbname=os.getenv("PGDATABASE", "eungsang_DB"),
)
cur = conn.cursor()
cur.execute(
    "SELECT table_name FROM information_schema.tables WHERE table_schema='public'"
)
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()
