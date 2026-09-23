# Bad: SQL query built from user input via format string (AP-PY-SEC-001 / S608)
def get_user(user_id):
    query = "SELECT * FROM users WHERE id = %s" % user_id
    cursor.execute(query)
    return cursor.fetchone()
