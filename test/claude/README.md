# AKS + NGINX Ingress con Internal Load Balancer (ILB)
## Documentación completa del proyecto Terraform

---

## 📐 Arquitectura de la Solución

```
┌─────────────────────────────────────────────────────────────────┐
│                    AZURE SUBSCRIPTION                           │
│                                                                 │
│  ┌─────────────────── Resource Group ──────────────────────┐   │
│  │                                                          │   │
│  │  ┌────────────────── VNet (10.0.0.0/16) ─────────────┐  │   │
│  │  │                                                    │  │   │
│  │  │  ┌── ILB Subnet ──┐   ┌─── AKS Node Subnet ───┐  │  │   │
│  │  │  │  10.0.4.0/27   │   │     10.0.0.0/22        │  │  │   │
│  │  │  │                │   │                        │  │  │   │
│  │  │  │  ┌──────────┐  │   │  ┌────┐  ┌────┐       │  │  │   │
│  │  │  │  │   ILB    │  │   │  │ N1 │  │ N2 │  ...  │  │  │   │
│  │  │  │  │ (priv.)  │  │   │  └────┘  └────┘       │  │  │   │
│  │  │  │  │10.0.4.10 │  │   │  ┌─────────────────┐  │  │  │   │
│  │  │  │  └────┬─────┘  │   │  │  NGINX Ingress   │  │  │   │  │
│  │  │  └───────┼────────┘   │  │   Controller     │  │  │   │  │
│  │  │          │            │  │   (2 réplicas)   │  │  │   │  │
│  │  │          └────────────→  └─────────┬───────┘  │  │  │   │
│  │  │                       │            │          │  │  │   │
│  │  │                       │  ┌─────────▼───────┐  │  │  │   │
│  │  │                       │  │   App Services   │  │  │  │   │
│  │  │                       │  │  (ClusterIP)     │  │  │  │   │
│  │  │                       │  └─────────────────┘  │  │  │   │
│  │  │                       └───────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │                                                          │   │
│  │  Otros recursos:                                         │   │
│  │  • Log Analytics Workspace (monitoreo)                   │   │
│  │  • Network Security Group (firewall de subnet)           │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

  Clientes de red interna
  (VPN / ExpressRoute / VNet Peering)
         │
         ▼
   ILB (10.0.4.10)  ← Solo accesible desde la red privada
         │
         ▼
  NGINX Ingress (enruta según host/path)
         │
         ▼
   App Kubernetes (pods)
```

---

## 📁 Estructura de Archivos

```
aks-nginx-ilb/
│
├── providers.tf          # Configuración de Terraform y providers (azurerm, helm, k8s)
├── variables.tf          # Declaración de variables con tipos y descripciones
├── terraform.tfvars      # Valores concretos para las variables
├── main.tf               # Recursos principales (RG, VNet, Subnets, AKS, Log Analytics)
├── nginx_ingress.tf      # Helm release de NGINX con configuración ILB
├── outputs.tf            # Outputs: IPs, IDs, comandos útiles
├── example_ingress.tf    # Ejemplo: app de prueba + objeto Ingress
└── README.md             # Esta documentación
```

---

## 🔑 Conceptos Clave

### 1. Azure CNI vs Kubenet
Este proyecto usa **Azure CNI** (`network_plugin = "azure"`):
- Cada pod recibe una IP **real** de la subnet de Azure (no solapada)
- Los pods son directamente accesibles desde la VNet
- Requiere más IPs que kubenet → subnet más grande (`/22`)
- Mejor rendimiento y menos latencia que kubenet

### 2. Cluster Autoscaler
El Cluster Autoscaler de Kubernetes monitorea:
- **Scale UP**: Pods en estado `Pending` → agrega nodos hasta `max_count`
- **Scale DOWN**: Nodos subutilizados por > `scale_down_unneeded` → elimina hasta `min_count`

```bash
# Verificar estado del autoscaler
kubectl describe configmap cluster-autoscaler-status -n kube-system
```

### 3. Internal Load Balancer (ILB) - La Pieza Central
El ILB se crea cuando Kubernetes ve un Service de tipo `LoadBalancer` con la anotación:

```yaml
annotations:
  service.beta.kubernetes.io/azure-load-balancer-internal: "true"
```

**Sin esta anotación** → Azure crea un Load Balancer público (IP pública, accesible desde Internet)  
**Con esta anotación** → Azure crea un ILB privado (IP de la VNet, solo accesible internamente)

### 4. Flujo de Tráfico Completo

```
1. Cliente (red interna) resuelve DNS: myapp.empresa.com → 10.0.4.10
2. Envía request HTTP/HTTPS a 10.0.4.10 (IP del ILB)
3. ILB recibe el tráfico y lo distribuye a los pods de NGINX (health checks activos)
4. NGINX lee el host header y los objetos Ingress del API Server
5. NGINX hace proxy del request al Service de Kubernetes de la app
6. El Service balancea entre los pods de la app
7. El pod procesa el request y responde
```

---

## 🚀 Guía de Despliegue

### Pre-requisitos
```bash
# Instalar Terraform
brew install terraform  # macOS
# o descargar desde: https://developer.hashicorp.com/terraform/downloads

# Instalar Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Instalar kubectl
az aks install-cli

# Instalar Helm
brew install helm
```

### Paso 1: Autenticación en Azure
```bash
# Login interactivo (desarrollo local)
az login

# Seleccionar suscripción correcta
az account set --subscription "<subscription-id>"

# Verificar
az account show
```

### Paso 2: Inicializar Terraform
```bash
cd aks-nginx-ilb/

# Inicializa: descarga providers, configura backend
terraform init

# Verificar que los providers se descargaron correctamente
terraform version
```

### Paso 3: Revisar el Plan
```bash
# Muestra QUÉ recursos se van a crear (sin crear nada)
terraform plan

# Guardar el plan para aplicarlo exactamente
terraform plan -out=tfplan

# Ver el plan en formato JSON (útil para auditoría)
terraform show -json tfplan | jq '.'
```

**Salida esperada del plan:**
```
Plan: 12 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aks_cluster_name         = "demo-aks"
  + ilb_private_ip           = "10.0.4.10"
  + nginx_ingress_namespace  = "ingress-nginx"
  ...
```

### Paso 4: Aplicar la Configuración
```bash
# Aplicar con confirmación interactiva
terraform apply

# O aplicar el plan guardado (sin confirmación)
terraform apply tfplan

# Para CI/CD (sin confirmación interactiva)
terraform apply -auto-approve
```

**Tiempo aproximado de despliegue:** 8-15 minutos
- Resource Group, VNet, Subnets: ~1 min
- AKS Cluster: ~5-10 min
- NGINX Ingress (Helm): ~2-3 min

### Paso 5: Verificar el Despliegue

```bash
# 1. Obtener kubeconfig
az aks get-credentials \
  --resource-group rg-aks-nginx-demo \
  --name demo-aks \
  --overwrite-existing

# 2. Verificar nodos
kubectl get nodes -o wide
# Esperado: 2 nodos en estado Ready

# 3. Verificar NGINX Ingress
kubectl get pods -n ingress-nginx
# Esperado: 2 pods ingress-nginx-controller en Running

# 4. *** VERIFICACIÓN CRÍTICA: IP del ILB ***
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Esperado: EXTERNAL-IP = 10.0.4.10 (la IP privada del ILB)

# 5. Verificar que el ILB existe en Azure
az network lb list \
  --resource-group $(terraform output -raw aks_node_resource_group) \
  --query "[].{Name:name, Type:sku.name}" \
  --output table
```

### Paso 6: Crear un Ingress de Prueba
```bash
# Aplicar el ejemplo incluido (example_ingress.tf ya lo hace via Terraform)
# O manualmente con kubectl:

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: example-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: test.internal.empresa.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-app
            port:
              number: 80
EOF

# Probar desde una VM dentro de la VNet:
curl -H "Host: test.internal.empresa.com" http://10.0.4.10/
```

---

## ⚙️ Personalización para Producción

### Múltiples Node Pools
Agregar en `main.tf`:
```hcl
resource "azurerm_kubernetes_cluster_node_pool" "user_pool" {
  name                  = "userpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_D4s_v3"
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 10
  vnet_subnet_id        = azurerm_subnet.aks_nodes.id
  
  node_labels = {
    "nodepool-type" = "user"
  }
  node_taints = []
}
```

### TLS con cert-manager
```hcl
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}
```

### Ingress con TLS
```yaml
spec:
  tls:
  - hosts:
    - myapp.internal.empresa.com
    secretName: myapp-tls
  rules:
  - host: myapp.internal.empresa.com
```

---

## 🗑️ Destruir los Recursos

```bash
# Elimina TODOS los recursos creados por Terraform
# ¡CUIDADO! Esta operación es irreversible
terraform destroy

# Para CI/CD:
terraform destroy -auto-approve
```

---

## 🔧 Troubleshooting

### El ILB no obtiene la IP privada configurada
```bash
# Ver eventos del Service
kubectl describe svc ingress-nginx-controller -n ingress-nginx

# Verificar que AKS tiene permisos sobre la subnet del ILB
az role assignment list --scope $(terraform output -raw ilb_subnet_id)
```

### Los pods de NGINX no arrancan
```bash
kubectl describe pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### El autoscaler no escala
```bash
# Ver logs del autoscaler
kubectl logs -n kube-system -l app=cluster-autoscaler

# Ver estado del autoscaler
kubectl describe configmap cluster-autoscaler-status -n kube-system
```

---

## 📊 Recursos Creados

| Recurso | Nombre | Descripción |
|---------|--------|-------------|
| Resource Group | rg-aks-nginx-demo | Contenedor de todos los recursos |
| Virtual Network | demo-vnet | Red privada del proyecto |
| Subnet (Nodos) | demo-aks-nodes-subnet | Subnet para VMs de AKS |
| Subnet (ILB) | demo-ilb-subnet | Subnet para el Load Balancer |
| NSG | demo-aks-nsg | Firewall de la subnet de nodos |
| AKS Cluster | demo-aks | Clúster Kubernetes gestionado |
| Log Analytics WS | demo-law | Workspace de monitoreo |
| NGINX Ingress | ingress-nginx | Helm release del Ingress Controller |
| ILB | (auto-generado) | Azure Internal Load Balancer |

**Total de recursos de Azure:** ~12 recursos directos + recursos gestionados por AKS en el MC_* Resource Group
