import sqlite3
from pathlib import Path

sql = (Path(__file__).parent / 'schema.sql').read_text()

conn = sqlite3.connect(":memory:")

conn.executescript(sql)

tables = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
indexes = conn.execute("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'").fetchall()

print("tables: ", [t[0] for t in tables])
print("indexes: ", [i[0] for i in indexes])