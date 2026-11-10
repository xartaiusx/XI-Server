import re


def migration_name():
    return "Preserve and update recast and GM audit columns"


def _column_type(cur, query, name):
    cur.execute(query)
    row = cur.fetchone()
    if not row:
        raise RuntimeError(f"Missing column {name}.")
    return row[1].lower()


def _needs_recast(cur):
    column = _column_type(
        cur, "SHOW COLUMNS FROM char_recast WHERE Field = 'recast';", "char_recast.recast"
    )
    if re.fullmatch(r"int(?:\(\d+\))? unsigned", column):
        return False
    if not re.fullmatch(r"smallint(?:\(\d+\))?(?: unsigned)?", column):
        raise RuntimeError("Unexpected char_recast.recast schema.")
    return True


def _needs_audit(cur):
    column = _column_type(
        cur, "SHOW COLUMNS FROM audit_gm WHERE Field = 'full_string';", "audit_gm.full_string"
    )
    if column == "blob":
        return False
    if column != "varchar(200)":
        raise RuntimeError("Unexpected audit_gm.full_string schema.")
    return True


def check_preconditions(cur):
    _needs_audit(cur)
    if _needs_recast(cur):
        cur.execute("SELECT 1 FROM char_recast WHERE recast < 0 LIMIT 1;")
        if cur.fetchone():
            raise RuntimeError(
                "char_recast.recast contains negative legacy values. "
                "The unsigned migration requires explicit resolution before proceeding."
            )


def needs_to_run(cur):
    return _needs_recast(cur) or _needs_audit(cur)


def migrate(cur, db):
    check_preconditions(cur)
    if _needs_recast(cur):
        cur.execute(
            "ALTER TABLE char_recast MODIFY recast int(10) unsigned NOT NULL DEFAULT '0';"
        )
    if _needs_audit(cur):
        cur.execute("ALTER TABLE audit_gm MODIFY full_string BLOB NOT NULL;")

    if needs_to_run(cur):
        raise RuntimeError("The recast and GM audit migrations did not take effect.")
    db.commit()
