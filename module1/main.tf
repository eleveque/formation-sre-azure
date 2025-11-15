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
  admin_enabled            = true     # On l'active pour se connecter facilement
}