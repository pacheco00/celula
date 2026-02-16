############################
# Variables de configuración
############################

variable "prefix" {
  description = "Prefijo para nombrar recursos"
  type        = string
  default     = "demo-aks-po"
}

variable "location" {
  description = "Región de Azure (ej: brazilsouth, eastus)"
  type        = string
  default     = "eastus"
}

variable "node_count" {
  description = "Número de nodos del pool por defecto"
  type        = number
  default     = 1
}
variable "vm_size" {
  description = "Tamaño de VM de los nodos"
  type        = string
  default     = "Standard_DS2_v2"
}
variable "env" {
  description = "ambiente"
  type        = string
  default     = "dev"
}

variable "apim_name" {
  description = "Nombre de la instancia APIM."
  type        = string
  default     = "apim"
}

variable "apim_publisher_name" {
  type    = string
  default = "Lab Publisher"
}

variable "apim_publisher_email" {
  type    = string
  default = "lab@example.com"
}

variable "api_base_path" {
  description = "Ruta base de la API del alumno (p.ej., alumnoX)."
  type        = string
  default     = "DevOps"
}

# ===== Variables KV / VNet PE =====
variable "kv_name" {
  description = "Nombre único del Key Vault."
  type        = string
  default     = null
}

variable "kv_vnet_cidr" {
  description = "CIDR para la VNet dedicada al Key Vault (Private Endpoint/APIM)."
  type        = list(string)
  default     = ["10.41.0.0/16"]
}

variable "kv_snet_pe_cidr" {
  description = "CIDR para la subred del Private Endpoint."
  type        = list(string)
  default     = ["10.41.1.0/24"]
}

variable "kv_snet_apim_cidr" {
  description = "CIDR para la subred de APIM (requisito: /24 y exclusiva)."
  type        = list(string)
  default     = ["10.41.2.0/24"]
}

variable "kv_snet_appgw_cidr" {
  description = "CIDR para la subred de APPGW (requisito: /24 y exclusiva)."
  type        = list(string)
  default     = ["10.41.3.0/24"]
}

# Secretos que usará APIM (Named Values) y microservicio (opcional)
variable "expected_api_key" {
  description = "Valor esperado del header X-Parse-REST-API-Key."
  type        = string
  default     = "2f5ae96c-b558-4c7b-a590-a501ae1c3f6c"
  sensitive   = true
}

variable "jwt_audience" {
  description = "Audiencia del JWT (p.ej., api://devops-lab)."
  type        = string
  default     = "api://devops-lab"
}

variable "jwt_secret" {
  description = "Secreto del microservicio (opcional)."
  type        = string
  default     = null
  sensitive   = true
}

# Override opcional para la IP del ILB (si en el primer plan aún no existe)
variable "ingress_ilb_ip_override" {
  description = "IP del ILB del Ingress NGINX (override opcional)."
  type        = string
  default     = null
}