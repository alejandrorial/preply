#!/usr/bin/env python3
"""
Ad-hoc SQL over the raw dataset with DuckDB, no dbt project needed.

Usage:
  python3 scripts/query.py                              # interactive prompt
  python3 scripts/query.py "select * from raw_payments limit 5"

Registers the three seed CSVs as views: raw_payments, raw_lessons, raw_students.
"""
import sys
from pathlib import Path

import duckdb

SEEDS = Path(__file__).parent.parent / "seeds"
TABLES = ["raw_payments", "raw_lessons", "raw_students"]


def connect():
    con = duckdb.connect()
    for name in TABLES:
        con.execute(f"create view {name} as select * from read_csv_auto('{SEEDS / (name + '.csv')}')")
    return con


def main():
    con = connect()

    if len(sys.argv) > 1:
        query = " ".join(sys.argv[1:])
        con.sql(query).show(max_width=200, max_rows=200)
        return

    print("Preply breakage — SQL sobre el dataset real (DuckDB).")
    print(f"Tablas disponibles: {', '.join(TABLES)}")
    print("Termina cada consulta en ';'. 'exit' para salir.\n")

    buf = ""
    while True:
        try:
            line = input("sql> " if not buf else "...> ")
        except EOFError:
            break
        if not buf and line.strip().lower() in ("exit", "quit"):
            break
        buf += line + "\n"
        if line.strip().endswith(";"):
            query = buf.strip().rstrip(";")
            buf = ""
            if not query:
                continue
            try:
                con.sql(query).show(max_width=200, max_rows=100)
            except Exception as e:
                print(f"Error: {e}")


if __name__ == "__main__":
    main()
