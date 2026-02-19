# =============================================================================
# terraform.tfvars
# Archivo de valores concretos para las variables del proyecto.
# Este archivo SOBREESCRIBE los valores default definidos en variables.tf.
#
# IMPORTANTE DE SEGURIDAD:
#   - Nunca versionar este archivo si contiene secretos o datos sensibles.
#   - Agregar "terraform.tfvars" al .gitignore para entornos con datos reales.
#   - Para CI/CD, usar variables de entorno: TF_VAR_<nombre_variable>
#     Ejemplo: export TF_VAR_resource_group_name="rg-prod-aks"
#
# Para distintos entornos, crear archivos separados:
#   - environments/dev.tfvars
#   - environments/staging.tfvars  
#   - environments/prod.tfvars
# Y aplicar con: terraform apply -var-file="environments/prod.tfvars"
# =============================================================================

# --- Configuración General ---
resource_group_name = "rg-aks-nginx-demo"
location            = "eastus2"
prefix              = "demo"

tags = {
  Environment = "demo"
  Project     = "aks-nginx-ilb"
  ManagedBy   = "Terraform"
  Owner       = "DevOps Team"
  CostCenter  = "IT-001"
}

# --- Configuración de Red ---
# Asegúrate de que estos CIDRs no se solapen con redes existentes
vnet_address_space = "10.0.0.0/16"
aks_subnet_cidr    = "10.0.0.0/22"
ilb_subnet_cidr    = "10.0.4.0/27"
service_cidr       = "10.100.0.0/16"
dns_service_ip     = "10.100.0.10"

# --- Configuración de AKS ---
kubernetes_version  = "1.29"
node_vm_size        = "Standard_D2s_v3"
node_initial_count  = 2
node_min_count      = 2
node_max_count      = 5

# --- Configuración de NGINX Ingress ---
nginx_helm_chart_version = "4.10.1"
nginx_namespace          = "ingress-nginx"
nginx_replica_count      = 2

# IP estática del ILB (debe estar dentro de ilb_subnet_cidr: 10.0.4.0/27)
# IPs disponibles: 10.0.4.4 - 10.0.4.30 (Azure reserva .0, .1, .2, .3, .31)
ilb_ip_address = "10.0.4.10"
