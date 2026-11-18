#!/bin/bash
set -e

RESOURCE_GROUP="rg-quizapp-eval"
IDENTITY_NAME="GitHubActions-OIDC"
LOCATION="francecentral"

echo -e "\n🔗 Configuration OIDC pour GitHub Actions"
echo "⚠️ Si GitHub utilise des IDs internes, copiez le 'subject' exact depuis les logs d'erreur."
read -p "👉 Entrez le 'subject' OIDC exact (ex: repo:user/repo:ref:refs/heads/main) ex: landry-sossa@63510797/eval-quiz-app_land-claud@1461213819 : " OIDC_SUBJECT

echo -e "\n1️⃣ Création de l'Identité Managée..."
az identity create --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --location $LOCATION > /dev/null

CLIENT_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query principalId -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo -e "⏳ Pause de 20 secondes pour laisser Azure synchroniser son annuaire..."
sleep 20

echo -e "2️⃣ Attribution des droits sur le groupe de ressources..."
az role assignment create --assignee $PRINCIPAL_ID --role contributor --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP > /dev/null

echo -e "3️⃣ Création du lien de confiance avec GitHub..."
az identity federated-credential create --name "GitHub-Trust" \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "$OIDC_SUBJECT" \
  --audiences "api://AzureADTokenExchange" > /dev/null

echo -e "\n✅ TERMINÉ ! Ajoutez ces 3 variables dans les Secrets de votre dépôt GitHub :"
echo "================================================================"
echo "AZURE_CLIENT_ID       : $CLIENT_ID"
echo "AZURE_TENANT_ID       : $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID : $SUBSCRIPTION_ID"
echo "================================================================"   