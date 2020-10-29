from flask import Flask
import os

from __init__ import db, login_manager
from views import view

app = Flask(__name__)

# Local test variables
_LOCAL_TESTING = False
_USERNAME = "administrator"
_PASSWORD = "password"
_HOST = "localhost"
_PORT = 5432
_DATABASE = "pcs_application"

# Routing
app.register_blueprint(view)

# Config
database_url = os.environ.get("DATABASE_URL", None)
if not database_url:
	database_url = "postgresql://{username}:{password}@{host}:{port}/{database}"\
    .format(
        username=_USERNAME,
        password=_PASSWORD,
        host=_HOST,
        port=_PORT,
        database=_DATABASE
    )
app.config["SQLALCHEMY_DATABASE_URI"] = database_url
app.config["SECRET_KEY"] = "A random key to use flask extensions that require encryption"

# Initialize other components
db.init_app(app)
login_manager.init_app(app)

with app.app_context():
	initFile = open(('FlaskApp/' if _LOCAL_TESTING else '') + 'sql/init.sql', 'r')
	db.session.execute(''.join(line.split('--')[0].strip() for line in initFile.readlines()))
	db.session.commit()
	initFile.close()

if __name__ == "__main__":
    app.run(
        debug=True,
        host="0.0.0.0",
        port=int(os.environ.get('PORT', 5000))
    )
