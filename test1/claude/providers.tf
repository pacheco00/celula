# =============================================================================
# providers.tf
# Configuración de los providers de Terraform necesarios para el proyecto.
#
# Un "provider" es el plugin que Terraform usa para comunicarse con una API.
# En este proyecto usamos tres providers:
#
#   1. azurerm  → Gestiona recursos de Azure (AKS, VNet, subnets, etc.)
#   2. helm     → Instala Helm Charts en Kubernetes
#   3. kubernetes → (Opcional) Gestiona recursos nativos de Kubernetes
# =============================================================================

terraform {
  # -------------------------------------------------------------------------
  # VERSIÓN DE TERRAFORM
  # Especificar la versión mínima de Terraform requerida.
  # ">= 1.5.0" significa: Terraform 1.5.0 o superior.
  # Fijar una versión mínima evita problemas de compatibilidad cuando
  # distintos miembros del equipo usan versiones diferentes.
  # -------------------------------------------------------------------------
  required_version = ">= 1.5.0"

  required_providers {
    # -----------------------------------------------------------------------
    # PROVIDER: azurerm
    # El provider oficial de HashiCorp para Microsoft Azure.
    # Gestiona más de 500 tipos de recursos de Azure.
    #
    # source: hashicorp/azurerm → registro oficial de Terraform
    # version: ~> 3.100 → permite 3.100.x pero no 4.x (semver ~>)
    # -----------------------------------------------------------------------
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }

    # -----------------------------------------------------------------------
    # PROVIDER: helm
    # Permite gestionar Helm Releases como recursos de Terraform.
    # Ventaja sobre Helm CLI: el estado queda en el state de Terraform,
    # y los cambios son reproducibles y versionados.
    # -----------------------------------------------------------------------
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }

    # -----------------------------------------------------------------------
    # PROVIDER: kubernetes
    # Gestiona recursos nativos de Kubernetes (Deployments, Services, etc.)
    # Útil para crear Ingress objects de ejemplo o configuraciones adicionales.
    # -----------------------------------------------------------------------
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }

  # -------------------------------------------------------------------------
  # BACKEND: ALMACENAMIENTO DEL STATE
  # El "state" de Terraform registra qué recursos han sido creados y su estado.
  # En equipos, el state DEBE almacenarse remotamente para:
  #   1. Compartirlo entre miembros del equipo.
  #   2. Evitar conflictos de state (state locking).
  #   3. Tener historial de cambios.
  #
  # DESCOMENTA el bloque siguiente para usar Azure Blob Storage como backend:
  #   - Crea primero: az storage account create + az storage container create
  #   - O usa el script de bootstrap incluido en scripts/bootstrap-backend.sh
  # -------------------------------------------------------------------------
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "tfstatedemo001"
  #   container_name       = "tfstate"
  #   key                  = "aks-nginx-ilb/terraform.tfstate"
  # }
}

# =============================================================================
# CONFIGURACIÓN DEL PROVIDER AZURERM
# =============================================================================
provider "azurerm" {
  # -------------------------------------------------------------------------
  # FEATURES: Configuraciones opcionales del provider.
  # El bloque vacío {} usa los valores por defecto, que son apropiados
  # para la mayoría de casos.
  #
  # Ejemplo de personalización:
  # features {
  #   resource_group {
  #     prevent_deletion_if_contains_resources = true  # Protección anti-borrado
  #   }
  #   key_vault {
  #     purge_soft_delete_on_destroy = false
  #   }
  # }
  # -------------------------------------------------------------------------
  features {}

  # -------------------------------------------------------------------------
  # AUTENTICACIÓN
  # El provider azurerm soporta múltiples métodos de autenticación:
  #
  # 1. Service Principal con Client Secret (recomendado para CI/CD):
  #    Configurar via variables de entorno:
  #      export ARM_SUBSCRIPTION_ID="<subscription-id>"
  #      export ARM_TENANT_ID="<tenant-id>"
  #      export ARM_CLIENT_ID="<client-id>"
  #      export ARM_CLIENT_SECRET="<client-secret>"
  #
  # 2. Azure CLI (recomendado para desarrollo local):
  #    Ejecutar: az login
  #    Terraform usa automáticamente las credenciales del CLI.
  #
  # 3. Managed Identity (recomendado si Terraform corre en Azure):
  #    use_msi = true  (en pipelines de Azure DevOps, VMs de Azure, etc.)
  #
  # NO hardcodear credenciales en el código. Usar variables de entorno o
  # Azure Key Vault para gestionar secretos.
  # -------------------------------------------------------------------------
}

# =============================================================================
# CONFIGURACIÓN DEL PROVIDER KUBERNETES
# Se configura después de que AKS existe (usando sus outputs).
# =============================================================================
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}
