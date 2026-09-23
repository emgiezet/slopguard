from django.db import connection, models
from sqlalchemy import text

# ok: slopguard.py.django-raw-sql-format
def get_user_by_email(email):
    return User.objects.raw('SELECT * FROM auth_user WHERE email = %s', [email])

# ok: slopguard.py.django-raw-sql-format
def search_users(query):
    with connection.cursor() as cursor:
        cursor.execute('SELECT * FROM users WHERE name LIKE %s', [f'%{query}%'])
        return cursor.fetchall()

# ok: slopguard.py.sqlalchemy-text-fstring
def get_active_orders(user_id):
    stmt = text('SELECT * FROM orders WHERE user_id = :uid AND status = :status')
    return db.execute(stmt, {'uid': user_id, 'status': 'active'}).fetchall()

# ok: slopguard.py.sqlalchemy-text-fstring
def search_products(keyword):
    stmt = text('SELECT * FROM products WHERE name LIKE :kw')
    return session.execute(stmt, {'kw': f'%{keyword}%'})
