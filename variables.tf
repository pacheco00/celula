variable "location" {
  type    = string
  default = "eastus"
}

variable "rg_name" {
  type    = string
  default = "rg-cloud-lab"
}

variable "vnet_name" {
  type    = string
  default = "vnet-aks-e00"
}

variable "vnet_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "subnet_aks_name" {
  type    = string
  default = "snet-aks-e00"
}

variable "subnet_aks_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "aks_name" {
  type    = string
  default = "aks-ilb-demo-e00"
}

variable "k8s_version" {
  type    = string
  default = "1.34.2" # ajusta a versión disponible
}

variable "node_size" {
  type    = string
  default = "Standard_DS2_v2" # Standard_D4s_v5
}

variable "min_nodes" {
  type    = number
  default = 2
}

variable "max_nodes" {
  type    = number
  default = 2
}

variable "node_count" {
  type    = number
  default = 2
}

# (Opcional) IP fija para el ILB dentro de la subnet del AKS
variable "ilb_static_ip" {
  type    = string
  default = "" # Ej: "10.10.1.10" o dejar vacío
}
