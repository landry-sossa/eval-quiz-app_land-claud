#!/bin/bash
# ==============================================================================
# Script: destroy.sh
# Description: Nettoyage complet de l'infrastructure Azure
# ==============================================================================

# Définition des couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

RESOURCE_GROUP="rg-quizapp-eval"

echo -e "${RED}⚠️ ATTENTION : Vous êtes sur le point de supprimer TOUTE l'infrastructure Azure ($RESOURCE_GROUP).${NC}"
echo -e "${YELLOW}Cela inclut le registre ACR, l'environnement, le frontend et le backend.${NC}"

read -p "Êtes-vous sûr de vouloir tout détruire ? (o/N) " confirm

if [[ "$confirm" =~ ^[oO|yY]$ ]]; then
    echo -e "\n${BLUE}🗑️ Lancement de la destruction (cela peut prendre quelques minutes)...${NC}"
    # L'option --yes évite la confirmation Azure, --no-wait rend la main au terminal immédiatement
    az group delete --name $RESOURCE_GROUP --yes --no-wait
    echo -e "${GREEN}✅ Commande envoyée ! Azure nettoie l'infrastructure en arrière-plan.${NC}"
else
    echo -e "\n${GREEN}🛑 Annulation. Rien n'a été supprimé.${NC}"
fi