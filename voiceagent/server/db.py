import os
import psycopg
from psycopg.rows import dict_row
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.environ["DATABASE_URL"]

def get_conn():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)

def rows(cur):
    return cur.fetchall()

def one(cur):
    return cur.fetchone()