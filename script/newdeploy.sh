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

# [MODIF] Nouvel environnement de type STANDARD (Workload profiles).
# L'ancien "env-quizapp" était en mode Express, qui ne supporte pas les
# domaines personnalisés (erreur ExpressCustomDomainsNotSupported).
ACA_ENV="env-quizapp-std"
OLD_ACA_ENV="env-quizapp"   # Ancien environnement Express (uniquement pour le détecter)

BACKEND_NAME="quiz-backend"
FRONTEND_NAME="quiz-frontend"

# [AJOUT] Domaine personnalisé à rattacher au frontend
CUSTOM_DOMAIN="g13.labformation.fr"
DOMAIN_BOUND="false"

echo -e "${BLUE}[INFO] Démarrage du processus de déploiement - Tag: v${VERSION}${NC}"

# ==========================================
# ETAPE 1 : Chargement de la configuration
# ==========================================
echo -e "\n${BLUE}[1/8] Chargement et sécurisation de la configuration...${NC}"
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
echo -e "\n${BLUE}[2/8] Vérification du Groupe de Ressources...${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION -o table

echo -e "\n${BLUE}[3/8] Vérification de l'Azure Container Registry (ACR)...${NC}"
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true -o table

echo -e "${YELLOW}[INFO] Récupération des identifiants du registre...${NC}"
ACR_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)

echo -e "${YELLOW}[INFO] Connexion de Docker au registre Azure...${NC}"
echo "$ACR_PASSWORD" | docker login $ACR_SERVER --username $ACR_USERNAME --password-stdin > /dev/null 2>&1

# ==========================================
# ETAPE 4 : Préparation et envoi des images
# ==========================================
echo -e "\n${BLUE}[4/8] Tag et Envoi des images Docker vers l'ACR...${NC}"

# [AJOUT] Vérification que les images locales existent avant de les taguer
for LOCAL_IMAGE in eval-quiz-app_land-claud-backend:latest eval-quiz-app_land-claud-frontend:latest; do
    if ! docker image inspect $LOCAL_IMAGE &>/dev/null; then
        echo -e "${RED}[ERREUR] L'image locale $LOCAL_IMAGE est introuvable. Construisez-la d'abord (docker compose build).${NC}"
        exit 1
    fi
done

docker tag eval-quiz-app_land-claud-backend:latest $ACR_SERVER/quiz-backend:$VERSION
docker tag eval-quiz-app_land-claud-frontend:latest $ACR_SERVER/quiz-frontend:$VERSION

docker push $ACR_SERVER/quiz-backend:$VERSION
docker push $ACR_SERVER/quiz-frontend:$VERSION

# ==========================================
# ETAPE 5 : Environnement Container Apps
# ==========================================
echo -e "\n${BLUE}[5/8] Vérification de l'environnement Azure Container Apps...${NC}"

# [AJOUT] Détection de l'ancien environnement Express (sans rien supprimer automatiquement)
if az containerapp env show --name $OLD_ACA_ENV --resource-group $RESOURCE_GROUP &>/dev/null; then
    echo -e "${YELLOW}[ATTENTION] L'ancien environnement '${OLD_ACA_ENV}' (Express) existe encore.${NC}"
    echo -e "${YELLOW}            Pour le nettoyer une fois la migration terminée :${NC}"
    echo -e "${YELLOW}              az containerapp env delete -n $OLD_ACA_ENV -g $RESOURCE_GROUP --yes${NC}"
fi

# [MODIF] --environment-mode WorkloadProfiles force un environnement standard (compatible domaines personnalisés).
# Sans ce paramètre, l'abonnement a créé un environnement Express, qui refuse les domaines personnalisés.
# On ne crée l'environnement que s'il n'existe pas, pour garder le script idempotent.
if az containerapp env show --name $ACA_ENV --resource-group $RESOURCE_GROUP &>/dev/null; then
    echo -e "${YELLOW}[INFO] L'environnement $ACA_ENV existe déjà. Aucune création nécessaire.${NC}"
else
    echo -e "${GREEN}[INFO] Création de l'environnement standard $ACA_ENV...${NC}"
    az containerapp env create --name $ACA_ENV --resource-group $RESOURCE_GROUP --location $LOCATION --environment-mode WorkloadProfiles --output table
fi

# [AJOUT] Contrôle du mode : on bloque si l'environnement est en Express (domaines personnalisés impossibles).
ENV_MODE=$(az containerapp env show --name $ACA_ENV --resource-group $RESOURCE_GROUP --query "properties.environmentMode" -o tsv)
if [ "$ENV_MODE" = "Express" ]; then
    echo -e "${RED}[ERREUR] L'environnement $ACA_ENV est en mode Express : les domaines personnalisés ne sont pas supportés.${NC}"
    echo -e "${RED}         Supprimez ses apps et l'environnement, puis relancez le script.${NC}"
    exit 1
fi
echo -e "${YELLOW}[INFO] Mode de l'environnement : ${ENV_MODE:-non renseigné}${NC}"

# [AJOUT] Garde-fou : un nom de Container App est unique dans un groupe de ressources.
# Si quiz-backend / quiz-frontend existent encore dans l'ancien environnement Express,
# le script ferait un "update" sur les anciennes apps au lieu de les créer dans le nouvel environnement.
ACA_ENV_ID=$(az containerapp env show --name $ACA_ENV --resource-group $RESOURCE_GROUP --query id -o tsv | tr '[:upper:]' '[:lower:]')
for APP_NAME in $BACKEND_NAME $FRONTEND_NAME; do
    if az containerapp show --name $APP_NAME --resource-group $RESOURCE_GROUP &>/dev/null; then
        APP_ENV_ID=$(az containerapp show --name $APP_NAME --resource-group $RESOURCE_GROUP --query "properties.environmentId || properties.managedEnvironmentId" -o tsv | tr '[:upper:]' '[:lower:]')
        if [ "$APP_ENV_ID" != "$ACA_ENV_ID" ]; then
            echo -e "${RED}[ERREUR] L'app $APP_NAME existe déjà dans un autre environnement (ancien Express).${NC}"
            echo -e "${RED}         Supprimez-la puis relancez le script :${NC}"
            echo -e "${RED}           az containerapp delete -n $APP_NAME -g $RESOURCE_GROUP --yes${NC}"
            exit 1
        fi
    fi
done

# # ==========================================
# # ETAPE 6 : Déploiement du Backend
# # ==========================================
# echo -e "\n${BLUE}[6/8] Déploiement du composant Backend...${NC}"
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


# ==========================================
# ETAPE 7 : Déploiement du Frontend
# ==========================================
# echo -e "\n${BLUE}[7/8] Déploiement du composant Frontend...${NC}"
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

# # ==========================================
# # ETAPE 8 : Domaine personnalisé (Frontend)
# # ==========================================
# # [AJOUT] Le frontend vient d'être déployé : on affiche les DNS à créer, puis on rattache
# # le domaine. Au premier lancement, le rattachement échoue tant que le CNAME et le TXT
# # ne sont pas créés et propagés : relancez simplement le script ensuite (idempotent).
# echo -e "\n${BLUE}[8/8] Configuration du domaine personnalisé (${CUSTOM_DOMAIN})...${NC}"

# # Le Verification ID est propre à l'environnement : il change si l'environnement change.
# ENV_VERIFICATION_ID=$(az containerapp env show --name $ACA_ENV --resource-group $RESOURCE_GROUP --query properties.customDomainConfiguration.customDomainVerificationId -o tsv)

# echo -e "${YELLOW}[INFO] Enregistrements DNS à créer chez le gestionnaire de la zone :${NC}"
# echo -e "       CNAME  ${CUSTOM_DOMAIN}  ->  ${FRONTEND_URL}"
# echo -e "       TXT    asuid.${CUSTOM_DOMAIN}  ->  ${ENV_VERIFICATION_ID}"

# # Le domaine est-il déjà rattaché à l'application ?
# ALREADY_BOUND=$(az containerapp hostname list --name $FRONTEND_NAME --resource-group $RESOURCE_GROUP --query "[?name=='${CUSTOM_DOMAIN}'] | length(@)" -o tsv)

# if [ "$ALREADY_BOUND" != "0" ] && [ -n "$ALREADY_BOUND" ]; then
#     echo -e "${YELLOW}[INFO] Le domaine ${CUSTOM_DOMAIN} est déjà rattaché. Rien à faire.${NC}"
#     DOMAIN_BOUND="true"
# else
#     echo -e "${GREEN}[INFO] Rattachement du domaine avec certificat managé (gratuit)...${NC}"
#     # Un échec (DNS pas encore propagé, par exemple) ne doit pas faire échouer tout le script.
#     # Si la validation du certificat échoue avec l'app en "scale to zero",
#     # passez temporairement le minimum de réplicas à 1, puis relancez.
#     if az containerapp hostname bind \
#         --hostname $CUSTOM_DOMAIN \
#         --name $FRONTEND_NAME \
#         --resource-group $RESOURCE_GROUP \
#         --environment $ACA_ENV \
#         --validation-method CNAME; then
#         echo -e "${GREEN}[SUCCES] Domaine ${CUSTOM_DOMAIN} rattaché.${NC}"
#         DOMAIN_BOUND="true"
#     else
#         echo -e "${YELLOW}[ATTENTION] Rattachement impossible pour le moment. Vérifiez que le CNAME et le TXT${NC}"
#         echo -e "${YELLOW}            ci-dessus sont créés et propagés, puis relancez ce script.${NC}"
#     fi
# fi

# ==========================================
# RESUME DU DEPLOIEMENT
# ==========================================
echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}[SUCCES] Deploiement termine avec succes !${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "🔗 ${BLUE}URL de l'API (Backend)${NC}       : https://$BACKEND_URL"
echo -e "🌐 ${BLUE}URL de l'Application (Frontend)${NC}: https://$FRONTEND_URL"
if [ "$DOMAIN_BOUND" = "true" ]; then
    echo -e "🌍 ${BLUE}Domaine personnalisé${NC}          : https://$CUSTOM_DOMAIN"
else
    echo -e "🌍 ${YELLOW}Domaine personnalisé en attente${NC} : créez le CNAME et le TXT (étape 8), puis relancez le script"
fi
echo -e "${GREEN}================================================================${NC}\n"
