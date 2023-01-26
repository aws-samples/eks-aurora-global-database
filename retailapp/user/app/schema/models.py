import psycopg2
from psycopg2.extras import RealDictCursor
import os
import time


def connect():
    rds_host = os.environ['DATABASE_HOST']
    db_user = os.environ['DATABASE_USER']
    password = os.environ['DATABASE_PASSWORD']
    db_name = os.environ['DATABASE_DB_NAME']
    rodb_name = os.environ['DATABASE_RODB_NAME']
    port = os.environ['DATABASE_PORT']
    ctr = 0
    while ctr <= 60:
       try:
          return psycopg2.connect(sslmode="prefer", host=rds_host, user=db_user, password=password, dbname=db_name, connect_timeout=10000, port=port, keepalives_interval=30)
       except:
          time.sleep(5)
          ctr = ctr + 1

class User:
    def __init__(self, db=connect()):
        try:
           self.cursor = db.cursor(cursor_factory=RealDictCursor)
        except:
           db=connect()
           self.cursor = db.cursor(cursor_factory=RealDictCursor)
        self.db = db
        self.user = None
        self.email = None

    def add(self, fname, lname, email, password):
        sql = f"INSERT INTO Users(fname, lname, email, password) VALUES(%s,%s,%s,%s);"
        data=(fname, lname, email, password)
        try:
           cur = self.db.cursor(cursor_factory=RealDictCursor)
           cur.execute(sql, data)
        except:
           self.db=connect()
           self.cursor = self.db.cursor(cursor_factory=RealDictCursor)
           cur = self.cursor
           cur.execute(sql, data)
        self.db.commit()
        cur.close()
        self.user = lname + ", " + fname
        self.email = email
        return {'fname': fname, 'lname': lname, 'email': email, 'password': password}

    def get(self, email):
        sql = "select fname, lname, email, id from Users where email='{}'".format(email)
        try:
           cur = self.db.cursor(cursor_factory=RealDictCursor)
           cur.execute(sql)
        except:
           self.db=connect()
           self.cursor = self.db.cursor(cursor_factory=RealDictCursor)
           cur = self.cursor
           cur.execute(sql)
        return cur.fetchall()

    def verify(self, email ,password):
        sql = "SELECT email, password FROM Users WHERE email='{}' AND password='{}'".format(email, password)
        try:
           cur = self.db.cursor(cursor_factory=RealDictCursor)
           cur.execute(sql)
        except:
           self.db=connect()
           self.cursor = self.db.cursor(cursor_factory=RealDictCursor)
           cur = self.cursor
           cur.execute(sql)
        result = cur.fetchall()
        self.db.commit()
        cur.close()
        row_count =  len(result)
        if row_count == 1 :
            return True
        else:
            return False

