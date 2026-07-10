"""List novel_docs_embeddings source files already ingested (local helper)."""

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
    "SELECT DISTINCT source_file FROM novel_docs_embeddings ORDER BY source_file"
)
processed_files = [row[0] for row in cur.fetchall()]
print(f"이미 처리된 파일 수: {len(processed_files)}")
for f in processed_files:
    print(f)

cur.close()
conn.close()
