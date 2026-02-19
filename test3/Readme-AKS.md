Crear AKS con NGINX Ingress privado usando Terraform

mi-infraestructura/
│
├── main.tf           ← el plano principal
├── variables.tf      ← las variables (como parámetros)
├── providers.tf      ← le dice a Terraform que use Azure
└── outputs.tf        ← lo que queremos ver al final

Herramientas que necesitas instalar
1. Terraform
2. Azure CLI
3. kubectl

ARCHIVO 1 — providers.tf
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# Conectar con Azure
provider "azurerm" {
  features {}
}

# Conectar Helm con el AKS que vamos a crear
provider "helm" {
  kubernetes {
    host = azurerm_kubernetes_cluster.aks.kube_config[0].host

    client_certificate = base64decode(
      azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate
    )
    client_key = base64decode(
      azurerm_kubernetes_cluster.aks.kube_config[0].client_key
    )
    cluster_ca_certificate = base64decode(
      azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate
    )
  }
}

ARCHIVO 2 — variables.tf
variable "resource_group_name" {
  description = "Nombre del grupo de recursos"
  default     = "rg-devops-proyecto"
}

variable "location" {
  description = "Región de Azure"
  default     = "eastus"
}

variable "cluster_name" {
  description = "Nombre del clúster AKS"
  default     = "aks-devops-cluster"
}

variable "node_count_min" {
  description = "Mínimo de nodos (máquinas)"
  default     = 1
}

variable "node_count_max" {
  description = "Máximo de nodos (máquinas)"
  default     = 3
}

variable "node_vm_size" {
  description = "Tamaño de las máquinas del clúster"
  default     = "Standard_D2s_v3"
}

ARCHIVO 3 — main.tf
Bloque 1 — Crear la carpeta en Azure
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

Bloque 2 — Crear el AKS con autoscaler
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "devops-aks"

  # Configuración del grupo de máquinas (nodos)
  default_node_pool {
    name       = "default"
    vm_size    = var.node_vm_size

    # ✅ Autoscaler habilitado
    enable_auto_scaling = true
    min_count           = var.node_count_min
    max_count           = var.node_count_max
  }

  # Cómo se identifica el AKS ante Azure
  identity {
    type = "SystemAssigned"
  }

  # Red interna del clúster
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }
}

Bloque 3 — Instalar NGINX con Helm 
resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  # ⭐ La parte más importante: hacer el LoadBalancer PRIVADO (ILB)
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-internal"
    value = "true"
  }

  # Puerto HTTP
  set {
    name  = "controller.service.ports.http"
    value = "80"
  }

  # Puerto HTTPS
  set {
    name  = "controller.service.ports.https"
    value = "443"
  }

  # Esperar a que NGINX esté listo antes de continuar
  wait    = true
  timeout = 300

  # NGINX necesita que el AKS exista primero
  depends_on = [azurerm_kubernetes_cluster.aks]
}

ARCHIVO 4 — outputs.tf
# Mostrar el nombre del cluster
output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

# Mostrar la IP privada del NGINX Ingress
output "ingress_ip" {
  description = "IP privada del NGINX Ingress (ILB)"
  value       = helm_release.nginx_ingress.status
}

# Comando para conectarse al cluster
output "kubectl_command" {
  value = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${var.cluster_name}"
}


PASO a PASO para ejecutarlo 
Paso 1 — Iniciar sesión en Azure
az login
Paso 2 — Preparar Terraform
terraform init
Paso 3 — Ver el plan antes de construir
terrafrom plan
Paso 4 — Construir todo
terraform apply
Paso 5 — Conectar kubectl al nuevo AKS
kubectl get pods -n ingress-nginx
Paso 7 — Ver la IP privada que asignó Azure
kubectl get service -n ingress-nginx


### Resumen visual de todo lo que se construyó 🗺️
```
Terraform apply
      │
      ├──► Grupo de Recursos (carpeta) 📁
      │
      ├──► AKS (centro comercial) 🏬
      │         │
      │         ├── Nodo 1 🖥️  ←── autoscaler
      │         ├── Nodo 2 🖥️  ←── (sube/baja solo)
      │         └── Nodo 3 🖥️
      │
      └──► NGINX Ingress (recepcionista) 🚦
                │
                └── ILB privado 🔒
                    IP: 10.240.0.8
                    (solo red interna,
                     internet NO puede entrar)