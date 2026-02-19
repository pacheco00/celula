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