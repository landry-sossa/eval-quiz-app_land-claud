#!/bin/bash
# ==============================================================================
# Script: deploy.sh
# Description: Déploiement automatisé et idempotent pour Azure Container Apps.
# Composants: ACR, ACA Environment, Backend (Node.js/PostgreSQL), Frontend (Nginx)
# ==============================================================================

set -e 

# --- Définition des couleurs pour l'affichage terminal ---
GREEN='\033[0;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Pas de couleur

# --- Versioning dynamique (Anti-Cache) ---
VERSION=$(date +%s)

# --- Configuration de l'infrastructure ---
RESOURCE_GROUP="rg-quizapp-eval"
LOCATION="francecentral"
ACR_NAME="acrquizappoet72" 
ACA_ENV="env-quizapp"
BACKEND_NAME="quiz-backend"
FRONTEND_NAME="quiz-frontend"

echo -e "${BLUE}[INFO] Démarrage du processus de déploiement - Tag: v${VERSION}${NC}"

# ==========================================
# ETAPE 1 : Chargement de la configuration
# ==========================================
echo -e "\n${BLUE}[1/7] Chargement et sécurisation de la configuration...${NC}"
if [ ! -f "azure.env" ]; then
    echo -e "${RED}[ERREUR] Le fichier azure.env est introuvable. Arrêt du script.${NC}"
    exit 1
fi

# Nettoyage des caractères de retour à la ligne Windows (\r)
tr -d '\r' < azure.env > azure.env.unix
set -a
source azure.env.unix
set +a
rm azure.env.unix
echo -e "${GREEN}[SUCCES] Configuration chargée.${NC}"

# ==========================================
# ETAPE 2 & 3 : Infrastructure de base (RG & ACR)
# ==========================================
echo -e "\n${BLUE}[2/7] Vérification du Groupe de Ressources...${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION -o table

echo -e "\n${BLUE}[3/7] Vérification de l'Azure Container Registry (ACR)...${NC}"
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true -o table

echo -e "${YELLOW}[INFO] Récupération des identifiants du registre...${NC}"
ACR_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv)

echo -e "${YELLOW}[INFO] Connexion de Docker au registre Azure...${NC}"
echo $ACR_PASSWORD | docker login $ACR_SERVER --username $ACR_USERNAME --password-stdin > /dev/null 2>&1

# ==========================================
# ETAPE 4 : Préparation et envoi des images
# ==========================================
# echo -e "\n${BLUE}[4/7] Tag et Envoi des images Docker vers l'ACR...${NC}"
# docker tag eval-quiz-app_land-claud-backend:latest $ACR_SERVER/quiz-backend:$VERSION
# docker tag eval-quiz-app_land-claud-frontend:latest $ACR_SERVER/quiz-frontend:$VERSION

# docker push $ACR_SERVER/quiz-backend:$VERSION
# docker push $ACR_SERVER/quiz-frontend:$VERSION

# ==========================================
# ETAPE 5 : Environnement Container Apps
# ==========================================
echo -e "\n${BLUE}[5/7] Vérification de l'environnement Azure Container Apps...${NC}"
az containerapp env create --name $ACA_ENV --resource-group $RESOURCE_GROUP --location $LOCATION --output table

# # ==========================================
# # ETAPE 6 : Déploiement du Backend
# # ==========================================
# echo -e "\n${BLUE}[6/7] Déploiement du composant Backend...${NC}"
# if az containerapp show --name $BACKEND_NAME --resource-group $RESOURCE_GROUP &>/dev/null; then
#     echo -e "${YELLOW}[INFO] Le conteneur existe déjà. Application de la mise à jour...${NC}"
#     az containerapp update \
#       --name $BACKEND_NAME \
#       --resource-group $RESOURCE_GROUP \
#       --image $ACR_SERVER/quiz-backend:$VERSION \
#       --set-env-vars "DATABASE_URL=$DATABASE_URL" "ADMIN_USERNAME=$ADMIN_USERNAME" "ADMIN_PASSWORD=$ADMIN_PASSWORD" "JWT_SECRET=$JWT_SECRET" "RESEND_API_KEY=$RESEND_API_KEY" "FROM_EMAIL=$FROM_EMAIL" \
#       --output table
# else
#     echo -e "${GREEN}[INFO] Premier déploiement du conteneur backend...${NC}"
#     az containerapp create \
#       --name $BACKEND_NAME \
#       --resource-group $RESOURCE_GROUP \
#       --environment $ACA_ENV \
#       --image $ACR_SERVER/quiz-backend:$VERSION \
#       --registry-server $ACR_SERVER \
#       --registry-username $ACR_USERNAME \
#       --registry-password $ACR_PASSWORD \
#       --target-port 3007 \
#       --ingress external \
#       --env-vars "DATABASE_URL=$DATABASE_URL" "ADMIN_USERNAME=$ADMIN_USERNAME" "ADMIN_PASSWORD=$ADMIN_PASSWORD" "JWT_SECRET=$JWT_SECRET" "RESEND_API_KEY=$RESEND_API_KEY" "FROM_EMAIL=$FROM_EMAIL" \
#       --output table
# fi

# echo -e "${YELLOW}[INFO] Récupération du FQDN du Backend...${NC}"
# BACKEND_URL=$(az containerapp show --name $BACKEND_NAME --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)

# # ==========================================
# # ETAPE 7 : Déploiement du Frontend
# # ==========================================
# echo -e "\n${BLUE}[7/7] Déploiement du composant Frontend...${NC}"
# if az containerapp show --name $FRONTEND_NAME --resource-group $RESOURCE_GROUP &>/dev/null; then
#     echo -e "${YELLOW}[INFO] Le conteneur existe déjà. Application de la mise à jour...${NC}"
#     az containerapp update \
#       --name $FRONTEND_NAME \
#       --resource-group $RESOURCE_GROUP \
#       --image $ACR_SERVER/quiz-frontend:$VERSION \
#       --set-env-vars "BACKEND_URL=https://$BACKEND_URL" \
#       --output table
# else
#     echo -e "${GREEN}[INFO] Premier déploiement du conteneur frontend...${NC}"
#     az containerapp create \
#       --name $FRONTEND_NAME \
#       --resource-group $RESOURCE_GROUP \
#       --environment $ACA_ENV \
#       --image $ACR_SERVER/quiz-frontend:$VERSION \
#       --registry-server $ACR_SERVER \
#       --registry-username $ACR_USERNAME \
#       --registry-password $ACR_PASSWORD \
#       --target-port 80 \
#       --ingress external \
#       --env-vars "BACKEND_URL=https://$BACKEND_URL" \
#       --output table
# fi

# FRONTEND_URL=$(az containerapp show --name $FRONTEND_NAME --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)

# ==========================================
# RESUME DU DEPLOIEMENT
# ==========================================
echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}[SUCCES] Deploiement termine avec succes !${NC}"
echo -e "${GREEN}================================================================${NC}"
# echo -e "🔗 ${BLUE}URL de l'API (Backend)${NC}       : https://$BACKEND_URL"
# echo -e "🌐 ${BLUE}URL de l'Application (Frontend)${NC}: https://$FRONTEND_URL"
# echo -e "${GREEN}================================================================${NC}\n"