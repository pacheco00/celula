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