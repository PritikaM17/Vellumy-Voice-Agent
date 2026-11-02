from pathlib import Path
from server.db import get_conn, rows

"""
establish the path for schema.sql for read full text as string
with get_conn make the connection to db
drop all schema and make a new public schema from schema.sql
start a new with cursor (cursor is a object used to run a query and then read results)
then the 1st query to select all the basetables and saving the results in table_rows, rows which is in db.py fetches all from query above
then query 2 for all indexes using Like idx_%
query 3 for views 
"""

sql = (Path(__file__).parent / "schema.sql").read_text()

with get_conn() as conn:
    conn.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    conn.execute(sql)

    with conn.cursor() as cur:

        cur.execute("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public'
                AND table_type = 'BASE TABLE'
            ORDER BY table_name
        """)

        table_rows = rows(cur)

        cur.execute("""
            SELECT indexname
            FROM pg_indexes
            WHERE schemaname = 'public'
                AND indexname LIKE 'idx_%'
        """)

        index_rows = rows(cur)

        cur.execute("""
            SELECT table_name
            FROM information_schema.views
            WHERE table_schema = 'public'
        """)

        view_rows = rows(cur)

    print(f"Tables ({len(table_rows)})")
    for row in table_rows:
        print(f"  - {row['table_name']}")

    print(f"Indexes ({len(index_rows)})")
    for row in index_rows:
        print(f"  - {row['indexname']}")
    
    print(f"Views ({len(view_rows)})")
    for row in view_rows:
        print(f"  - {row['table_name']}")

    conn.rollback()