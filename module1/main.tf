# -----------------------------------------------------------------
# Bloc 1 : Configuration de Terraform
# On dit à Terraform quels "fournisseurs" (plugins) on utilise.
# -----------------------------------------------------------------
terraform {
  required_providers {
    # On a besoin du fournisseur 'azurerm' (pour Azure)
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0" # On fixe une version pour la stabilité
    }
    # On a besoin du fournisseur 'random' (pour générer un nom unique)
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
    github = {
      source  = "integrations/github"
      version = "~>5.0" # Une version récente
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>2.0"
    }
  }
}

# -----------------------------------------------------------------
# Bloc 2 : Configuration du Fournisseur
# On dit à Terraform comment se connecter à Azure.
# -----------------------------------------------------------------
provider "azurerm" {
  # Pas besoin de clés ici, il utilisera votre 'az login' !
  features {}
}

provider "github" {
  # Le nom de votre organisation/utilisateur GitHub
  owner = "eleveque" 
}

provider "azuread" {
  # Pas besoin de config spéciale, il utilise votre connexion Azure actuelle
}

# -----------------------------------------------------------------
# Bloc 3 : Votre Infrastructure (Ce que vous créez)
# -----------------------------------------------------------------

# Ressource 1 : Le Groupe de Ressources (le "dossier")
# C'est 100% gratuit, c'est juste une organisation logique.
resource "azurerm_resource_group" "rg_formation" {
  name     = "rg-sre-formation-tp1" # Nom de votre groupe de ressources
  location = "West Europe"          # Région (Amsterdam). Vous pouvez mettre "France Central"
}

# Ressource 2 : Un générateur de nom aléatoire
# Les comptes de stockage doivent avoir un nom unique au monde.
# On utilise cet outil pour générer une chaîne de caractères aléatoire.
resource "random_id" "id_stockage" {
  byte_length = 4
}

# Ressource 3 : Le Compte de Stockage (le "disque dur")
# C'est là que le Free Tier entre en jeu.
resource "azurerm_storage_account" "sa_formation" {
  # Le nom est composé d'un préfixe + la chaîne aléatoire
  name                     = "stformationsre${random_id.id_stockage.hex}"
  
  # On dit à Terraform de créer cette ressource DANS le groupe de ressources
  # créé juste au-dessus. Terraform comprend la dépendance.
  resource_group_name      = azurerm_resource_group.rg_formation.name
  location                 = azurerm_resource_group.rg_formation.location

  # --- Paramètres "Zéro Euro" ---
  account_tier             = "Standard"     # Le seul type éligible au Free Tier
  account_replication_type = "LRS"          # "Locally-redundant storage". C'est le moins cher
                                            # et c'est inclus dans les 5Go gratuits / 12 mois.
}

# -----------------------------------------------------------------
# Bloc 4 : L'Entrepôt d'Images Docker (ACR)
# -----------------------------------------------------------------
resource "azurerm_container_registry" "acr_formation" {
  name                     = "acrformationsre${random_id.id_stockage.hex}" # Nom unique
  resource_group_name      = azurerm_resource_group.rg_formation.name
  location                 = azurerm_resource_group.rg_formation.location

  # --- Paramètres "Zéro Euro" ---
  sku                      = "Basic"  # Le plan "Basic" est inclus dans le Free Tier 12 mois.
  admin_enabled            = false     # On l'active pour se connecter facilement
}


# -----------------------------------------------------------------
# Bloc 5 : Le Cluster Kubernetes (AKS)
# -----------------------------------------------------------------

# On crée une "Identité" (un "robot") pour notre cluster K8s
# Il l'utilisera pour parler aux autres services Azure (comme l'ACR)
resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = "aks-identity-sre"
  resource_group_name = azurerm_resource_group.rg_formation.name
  location            = azurerm_resource_group.rg_formation.location
}

resource "random_uuid" "role_uuid" {
}

resource "random_uuid" "role_uuid_mi_op" {
}

resource "azurerm_log_analytics_workspace" "logs_formation" {
  name                = "logs-sre-formation"
  location            = azurerm_resource_group.rg_formation.location
  resource_group_name = azurerm_resource_group.rg_formation.name
  sku                 = "PerGB2018" # Le plan standard "Pay-as-you-go"
  retention_in_days   = 30
}

# On donne à ce "robot" la permission "AcrPull" (tirer les images)
# sur notre entrepôt ACR.
resource "azurerm_role_assignment" "aks_pull_acr" {
  # On utilise 'guid' pour un nom de rôle unique
  name                 = random_uuid.role_uuid.result
  
  scope                = azurerm_container_registry.acr_formation.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

resource "azurerm_role_assignment" "aks_manage_identity" {
  name                 = random_uuid.role_uuid_mi_op.result
  
  # L'Ouvrier (la ressource sur laquelle on donne la permission)
  scope                = azurerm_user_assigned_identity.aks_identity.id 
  
  # La permission
  role_definition_name = "Managed Identity Operator" 
  
  # Le Cerveau (celui qui reçoit la permission)
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# Enfin, on déclare le cluster Kubernetes lui-même
resource "azurerm_kubernetes_cluster" "aks_formation" {
  name                = "aks-formation-sre"
  resource_group_name = azurerm_resource_group.rg_formation.name
  location            = azurerm_resource_group.rg_formation.location
  dns_prefix          = "aks-sre-formation"

  depends_on = [
    azurerm_role_assignment.aks_pull_acr
  ]

  # On définit le "pool" de VMs (les serveurs) qui vont 
  # exécuter nos conteneurs.
  default_node_pool {
    name       = "default"
    node_count = 1                # On n'en prend qu'une pour limiter les coûts
    vm_size    = "Standard_B2s"   # Une taille minimale pour K8s
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.logs_formation.id
  }
  
  # On assigne notre "robot" au cluster
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_identity.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.aks_identity.client_id
    object_id                 = azurerm_user_assigned_identity.aks_identity.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.aks_identity.id
  }
}

# -----------------------------------------------------------------
# Bloc 8 : Automatisation GitHub (Module 5)
# -----------------------------------------------------------------
resource "github_actions_variable" "acr_url" {
  # Nom du dépôt
  repository    = "formation-sre-azure"
  
  # ATTENTION : C'est 'variable_name', pas 'name' !
  variable_name = "ACR_LOGIN_SERVER"
  
  # La valeur (l'URL de l'ACR)
  value         = azurerm_container_registry.acr_formation.login_server
}


# 1. On récupère la config actuelle (pour connaître votre Tenant ID)
data "azurerm_client_config" "current" {}

# 2. On crée l'Application (La définition du robot)
resource "azuread_application" "github_app" {
  display_name = "github-actions-sre-terraform"
}

# 3. On crée le Service Principal (L'instance du robot)
resource "azuread_service_principal" "github_sp" {
  client_id = azuread_application.github_app.client_id
}

# 4. On configure la Fédération OIDC (La confiance avec GitHub)
resource "azuread_application_federated_identity_credential" "github_oidc" {
  application_id = azuread_application.github_app.id
  display_name   = "github-actions-trust"
  description    = "Confiance OIDC gérée par Terraform"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  # ATTENTION : Remplacez par votre user/repo exact !
  subject        = "repo:eleveque/formation-sre-azure:ref:refs/heads/main"
}

# 5. On donne la permission AcrPush au NOUVEAU robot
resource "azurerm_role_assignment" "github_push_acr" {
  role_definition_name = "AcrPush"
  scope                = azurerm_container_registry.acr_formation.id
  # On utilise l'ID du robot que Terraform vient de créer
  principal_id         = azuread_service_principal.github_sp.object_id
}

# 6. On envoie le NOUVEAU Client ID directement dans les secrets GitHub !
resource "github_actions_secret" "client_id" {
  repository      = "formation-sre-azure"
  secret_name     = "AZURE_CLIENT_ID"
  # C'est ici que la boucle est bouclée : Terraform connaît l'ID, il l'envoie.
  plaintext_value = azuread_application.github_app.client_id
}

# 7. (Bonus) On met à jour les autres secrets pour être sûr
resource "github_actions_secret" "subscription_id" {
  repository      = "formation-sre-azure"
  secret_name     = "AZURE_SUBSCRIPTION_ID"
  plaintext_value = data.azurerm_client_config.current.subscription_id
}

resource "github_actions_secret" "tenant_id" {
  repository      = "formation-sre-azure"
  secret_name     = "AZURE_TENANT_ID"
  plaintext_value = data.azurerm_client_config.current.tenant_id
}