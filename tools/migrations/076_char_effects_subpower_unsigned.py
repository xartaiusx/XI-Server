def migration_name():
    return "Make char_effects subpower unsigned to match the server"


def check_preconditions(cur):
    if needs_to_run(cur):
        cur.execute("SELECT 1 FROM char_effects WHERE subpower < 0 LIMIT 1;")
        if cur.fetchone():
            raise RuntimeError(
                "char_effects.subpower contains negative legacy values. "
                "The unsigned migration requires explicit resolution before proceeding."
            )


def needs_to_run(cur):
    cur.execute("SHOW COLUMNS FROM char_effects WHERE Field = 'subpower';")
    column = cur.fetchone()
    if not column or not column[1].lower().startswith("smallint"):
        raise RuntimeError("Unexpected char_effects.subpower schema.")
    return "unsigned" not in column[1].lower()


def migrate(cur, db):
    check_preconditions(cur)
    if not needs_to_run(cur):
        return

    cur.execute(
        "ALTER TABLE char_effects MODIFY subpower smallint(5) unsigned NOT NULL DEFAULT '0';"
    )
    if needs_to_run(cur):
        raise RuntimeError("The char_effects.subpower migration did not take effect.")
    db.commit()
