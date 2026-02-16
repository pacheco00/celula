# =============================================================================
# outputs.tf
# Define los valores que Terraform muestra al terminar el apply, y que
# pueden ser consumidos por otros módulos o scripts.
#
# Los outputs son útiles para:
#   1. Obtener información de recursos creados (IPs, nombres, IDs).
#   2. Pasar valores entre módulos de Terraform.
#   3. Integrar con pipelines de CI/CD (ej: kubectl, helm, etc.).
# =============================================================================

# -----------------------------------------------------------------------------
# OUTPUTS DEL RESOURCE GROUP
# -----------------------------------------------------------------------------
output "resource_group_name" {
  description = "Nombre del Resource Group creado."
  value       = azurerm_resource_group.rg.name
}

output "resource_group_id" {
  description = "ID de Azure del Resource Group."
  value       = azurerm_resource_group.rg.id
}

# -----------------------------------------------------------------------------
# OUTPUTS DEL CLÚSTER AKS
# -----------------------------------------------------------------------------
output "aks_cluster_name" {
  description = "Nombre del clúster AKS."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_id" {
  description = "ID de Azure del clúster AKS."
  value       = azurerm_kubernetes_cluster.aks.id
}

output "aks_node_resource_group" {
  description = <<-EOT
    Resource Group donde AKS crea los recursos de infraestructura de los nodos
    (VMs, discos, NICs, Load Balancers). Azure lo crea automáticamente con el
    nombre "MC_<rg>_<aks-name>_<location>".
    Los recursos del ILB aparecerán aquí.
  EOT
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "aks_kubernetes_version" {
  description = "Versión de Kubernetes instalada en el clúster."
  value       = azurerm_kubernetes_cluster.aks.kubernetes_version
}

# -----------------------------------------------------------------------------
# OUTPUTS DE IDENTIDAD DEL CLÚSTER
# La identidad del clúster se usa para asignar roles RBAC de Azure.
# Necesaria para dar acceso a ACR, Key Vault, etc.
# -----------------------------------------------------------------------------
output "aks_identity_principal_id" {
  description = "Principal ID de la Managed Identity del clúster AKS."
  value       = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

output "aks_kubelet_identity_client_id" {
  description = "Client ID de la identidad del kubelet (usada por los nodos)."
  value       = azurerm_kubernetes_cluster.aks.kubelet_identity[0].client_id
}

# -----------------------------------------------------------------------------
# OUTPUTS DE KUBECONFIG
# Las credenciales para conectarse al clúster.
# IMPORTANTE: Marcar como sensitive = true para que Terraform no las muestre
# en la consola ni en los logs.
# -----------------------------------------------------------------------------
output "kube_config_raw" {
  description = <<-EOT
    Kubeconfig completo para conectarse al clúster.
    Para usar: terraform output -raw kube_config_raw > ~/.kube/config
    O: export KUBECONFIG=<(terraform output -raw kube_config_raw)
  EOT
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

output "aks_api_server_url" {
  description = "URL del API Server de Kubernetes."
  value       = azurerm_kubernetes_cluster.aks.kube_config[0].host
  sensitive   = true
}

# -----------------------------------------------------------------------------
# OUTPUTS DE RED
# -----------------------------------------------------------------------------
output "vnet_id" {
  description = "ID de la Virtual Network."
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "Nombre de la Virtual Network."
  value       = azurerm_virtual_network.vnet.name
}

output "aks_subnet_id" {
  description = "ID de la subnet de nodos AKS."
  value       = azurerm_subnet.aks_nodes.id
}

output "ilb_subnet_id" {
  description = "ID de la subnet del Internal Load Balancer."
  value       = azurerm_subnet.ilb.id
}

output "ilb_private_ip" {
  description = <<-EOT
    IP privada del Internal Load Balancer de NGINX.
    Esta es la IP a la que deben apuntar los registros DNS internos
    y los clientes que consumen los servicios expuestos por el Ingress.
    Ejemplo de uso:
      - Registro DNS interno: myapp.internal.empresa.com → 10.0.4.10
      - Regla de firewall: permitir tráfico HTTPS hacia 10.0.4.10
  EOT
  value       = var.ilb_ip_address
}

# -----------------------------------------------------------------------------
# OUTPUTS DE NGINX INGRESS
# -----------------------------------------------------------------------------
output "nginx_ingress_namespace" {
  description = "Namespace de Kubernetes donde está instalado NGINX Ingress."
  value       = var.nginx_namespace
}

output "nginx_helm_release_status" {
  description = "Estado del Helm Release de NGINX Ingress (deployed, failed, etc.)."
  value       = helm_release.nginx_ingress.status
}

# -----------------------------------------------------------------------------
# OUTPUTS DE LOG ANALYTICS
# -----------------------------------------------------------------------------
output "log_analytics_workspace_id" {
  description = "ID del Log Analytics Workspace para consultas de logs."
  value       = azurerm_log_analytics_workspace.law.id
}

output "log_analytics_workspace_name" {
  description = "Nombre del Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.law.name
}

# -----------------------------------------------------------------------------
# COMANDOS DE USO (como outputs de tipo string)
# Outputs informativos que muestran comandos útiles post-deploy.
# -----------------------------------------------------------------------------
output "cmd_get_kubeconfig" {
  description = "Comando para obtener el kubeconfig del clúster AKS."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
}

output "cmd_verify_ilb" {
  description = "Comando para verificar que el ILB fue creado con la IP privada correcta."
  value       = "kubectl get svc -n ${var.nginx_namespace} ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

output "cmd_verify_nodes" {
  description = "Comando para verificar los nodos del clúster y el autoscaler."
  value       = "kubectl get nodes -o wide && kubectl describe configmap cluster-autoscaler-status -n kube-system"
}
