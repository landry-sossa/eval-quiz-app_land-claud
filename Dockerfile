# Étape 1 : Build de l'application avec Node
FROM node:20-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Étape 2 : Serveur web Nginx avec configuration personnalisée
FROM nginx:alpine

# 1. On supprime la configuration Nginx par défaut
RUN rm /etc/nginx/conf.d/default.conf

# # 2. On copie ma config nginx pour dockercompose
# COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf

# 2.1 On copie ma config nginx pour azure
COPY nginx/azure.nginx.conf /etc/nginx/conf.d/default.conf


# 3. On copie les fichiers statiques compilés
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]