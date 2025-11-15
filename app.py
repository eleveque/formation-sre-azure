from flask import Flask
import os

app = Flask(__name__)

# On récupère le nom du "pod" (le conteneur)
hostname = os.environ.get('HOSTNAME', 'Inconnu')

@app.route('/')
def hello():
    return f"<h1>Bonjour !</h1><p>Je suis servi depuis le conteneur : {hostname}</p>"

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)