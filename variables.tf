variable "location"            { type = string  default = "eastus" }
variable "rg_name"             { type = string  default = "rg-aks-ilb" }
variable "vnet_name"           { type = string  default = "vnet-aks" }
variable "vnet_cidr"           { type = string  default = "10.10.0.0/16" }
variable "subnet_aks_name"     { type = string  default = "snet-aks" }
variable "subnet_aks_cidr"     { type = string  default = "10.10.1.0/24" }

variable "aks_name"            { type = string  default = "aks-ilb-demo" }
variable "k8s_version"         { type = string  default = "1.29.7" } # ajusta a versión disponible
variable "node_size"           { type = string  default = "Standard_D4s_v5" }
variable "min_nodes"           { type = number  default = 2 }
variable "max_nodes"           { type = number  default = 6 }
variable "node_count"          { type = number  default = 2 }

# (Opcional) IP fija para el ILB dentro de la subnet del AKS
variable "ilb_static_ip"       { type = string  default = "" } # Ej: "10.10.1.10" o dejar vacío
