# Utilisation d'une image légère Alpine pour réduire la surface d'attaque et le poids
FROM node:20-alpine

WORKDIR /app

# Copie des fichiers de dépendances en premier pour optimiser le cache Docker
COPY package*.json ./
RUN npm install

# Copie du code source
COPY . .

EXPOSE 3007

# Démarrage de l'application
CMD ["npm", "start"]