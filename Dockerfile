# Étape 1 : On part d'une image de base officielle (Python 3.9 slim)
FROM python:3.9-slim

# Étape 2 : On définit le dossier de travail A L'INTERIEUR du conteneur
WORKDIR /app

# Étape 3 : On copie le fichier des dépendances
COPY requirements.txt .

# Étape 4 : On installe les dépendances A L'INTERIEUR du conteneur
RUN pip install -r requirements.txt

# Étape 5 : On copie notre code source
COPY app.py .

# Étape 6 : On expose le port 5000 (le port de Flask)
EXPOSE 5000

# Étape 7 : La commande pour démarrer l'application
CMD ["flask", "run", "--host=0.0.0.0", "--port=5000"]