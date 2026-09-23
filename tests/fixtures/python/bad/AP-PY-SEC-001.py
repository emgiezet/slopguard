from django.db import connection, models
from sqlalchemy import text

# ruleid: slopguard.py.django-raw-sql-format
def get_user_by_email(email):
    return User.objects.raw(f"SELECT * FROM auth_user WHERE email = '{email}'")

# ruleid: slopguard.py.django-raw-sql-format
def search_users(query):
    with connection.cursor() as cursor:
        cursor.execute("SELECT * FROM users WHERE name LIKE '%" + query + "%'")
        return cursor.fetchall()

# ruleid: slopguard.py.sqlalchemy-text-fstring
def get_active_orders(user_id):
    stmt = text(f"SELECT * FROM orders WHERE user_id = {user_id} AND status = 'active'")
    return db.execute(stmt).fetchall()

# ruleid: slopguard.py.sqlalchemy-text-fstring
def search_products(keyword):
    return session.execute(text("SELECT * FROM products WHERE name LIKE '%{}%'".format(keyword)))
