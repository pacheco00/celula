# =============================================================================
# nginx_ingress.tf
# Instalación de NGINX Ingress Controller mediante Helm con configuración
# para Internal Load Balancer (ILB) privado en Azure.
#
# Flujo del tráfico con esta configuración:
#   Cliente (red interna) → ILB (IP privada) → NGINX Pod → App Pod
#
# El ILB es PRIVADO: solo accesible desde dentro de la VNet o redes conectadas
# (VPN, ExpressRoute, VNet Peering). No tiene IP pública.
# =============================================================================

# -----------------------------------------------------------------------------
# HELM PROVIDER - CONEXIÓN AL CLÚSTER AKS
# El provider de Helm necesita credenciales para conectarse al API Server
# de Kubernetes y ejecutar operaciones de Helm (install, upgrade, etc.).
#
# Usamos los datos de conexión que AKS expone directamente como outputs:
#   - host: URL del API Server
#   - client_certificate/client_key: credenciales del cliente TLS
#   - cluster_ca_certificate: certificado de la CA del clúster
#
# IMPORTANTE: Este bloque se coloca aquí (en lugar de providers.tf) para
# mantener juntas la configuración del provider y el recurso helm_release,
# pero en proyectos grandes conviene moverlo a providers.tf.
# -----------------------------------------------------------------------------
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

# -----------------------------------------------------------------------------
# HELM RELEASE: NGINX INGRESS CONTROLLER
#
# ¿Qué es un Helm Release?
#   Es una instancia instalada de un Helm Chart en el clúster.
#   Helm empaqueta todos los recursos de Kubernetes (Deployment, Service,
#   ConfigMap, RBAC, etc.) necesarios para NGINX en un solo Chart.
#
# ¿Por qué NGINX Ingress Controller?
#   - Es el Ingress Controller más popular para Kubernetes.
#   - Permite enrutar tráfico HTTP/HTTPS a distintos servicios según:
#     * Host (dominio): api.empresa.com → service-api
#     * Path (ruta):    empresa.com/app → service-app
#   - Soporta TLS termination, rate limiting, autenticación, etc.
#
# Chart utilizado: ingress-nginx/ingress-nginx (oficial de la comunidad K8s)
# Repositorio: https://kubernetes.github.io/ingress-nginx
# -----------------------------------------------------------------------------
resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.nginx_helm_chart_version
  namespace        = var.nginx_namespace
  create_namespace = true  # Crea el namespace si no existe

  # ---------------------------------------------------------------------------
  # ATOMIC: Si la instalación falla, Helm hace rollback automático.
  # Sin esta opción, una instalación fallida puede dejar recursos a medias.
  # ---------------------------------------------------------------------------
  atomic          = true
  cleanup_on_fail = true

  # Tiempo máximo de espera para que el deployment esté listo
  timeout = 300 # 5 minutos

  # ---------------------------------------------------------------------------
  # VALUES DEL CHART
  # Estos son los parámetros que personalizan el comportamiento de NGINX.
  # Equivale a un archivo values.yaml pasado con: helm install -f values.yaml
  #
  # La estructura sigue la jerarquía del chart:
  #   controller → configuración del NGINX Ingress Controller
  #     service  → configuración del Service de Kubernetes (el que crea el ILB)
  #       annotations → metadatos especiales que Azure lee para configurar el ILB
  # ---------------------------------------------------------------------------

  # ===========================================================================
  # ANOTACIÓN CRÍTICA #1: azure-load-balancer-internal
  # "service.beta.kubernetes.io/azure-load-balancer-internal: true"
  #
  # Esta es LA anotación más importante de toda la configuración.
  # Sin ella, Azure crearía un Load Balancer PÚBLICO (con IP pública).
  # Con ella, Azure crea un Internal Load Balancer (ILB) con IP PRIVADA.
  #
  # ¿Cómo funciona?
  # Cuando Kubernetes crea un Service de tipo LoadBalancer en AKS, el
  # Cloud Controller Manager de Azure intercepta el evento y crea un
  # Azure Load Balancer. Las anotaciones en el Service le indican qué
  # tipo de LB crear y cómo configurarlo.
  # ===========================================================================
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-internal"
    value = "true"
  }

  # ===========================================================================
  # ANOTACIÓN CRÍTICA #2: azure-load-balancer-internal-subnet
  # Especifica en QUÉ SUBNET crear el ILB.
  #
  # Aunque no es estrictamente obligatoria (Azure elige la subnet de los nodos
  # por defecto), es una BEST PRACTICE especificarla porque:
  #   1. Da control explícito sobre dónde vive el punto de entrada.
  #   2. Permite separar el tráfico de entrada del tráfico interno de nodos.
  #   3. Facilita aplicar NSGs específicos a la subnet del ILB.
  #   4. Evita conflictos de IPs con los nodos AKS.
  # ===========================================================================
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-internal-subnet"
    value = "${var.prefix}-ilb-subnet"
  }

  # ===========================================================================
  # IP ESTÁTICA DEL ILB
  # Fija la IP privada del ILB. Sin esto, Azure asignaría una IP dinámica
  # que puede cambiar con cada redeploy.
  #
  # IMPORTANTE: Esta IP debe:
  #   1. Estar dentro del CIDR de ilb_subnet (10.0.4.0/27).
  #   2. No estar ya en uso por otro recurso.
  #   3. No ser una IP reservada por Azure (.0, .1, .2, .3 y la última del rango).
  #
  # Una IP estática es esencial para:
  #   - Registros DNS internos (apuntar un dominio a la IP del ILB).
  #   - Reglas de firewall corporativas (whitelist de la IP).
  #   - Configuraciones de clientes que apuntan directamente a la IP.
  # ===========================================================================
  set {
    name  = "controller.service.loadBalancerIP"
    value = var.ilb_ip_address
  }

  # Tipo de Service: LoadBalancer → Azure crea el ILB
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  # ===========================================================================
  # RÉPLICAS DEL CONTROLLER
  # Número de pods de NGINX Ingress Controller corriendo simultáneamente.
  # Con 2 réplicas:
  #   - Si un pod falla, el otro sigue atendiendo tráfico (HA).
  #   - El ILB distribuye el tráfico entre ambas réplicas automáticamente.
  #   - Ambos pods leen la misma configuración de los objetos Ingress.
  # ===========================================================================
  set {
    name  = "controller.replicaCount"
    value = var.nginx_replica_count
  }

  # ===========================================================================
  # RECURSOS DE CPU Y MEMORIA
  # Importante para el Cluster Autoscaler: los requests son lo que el scheduler
  # usa para decidir en qué nodo colocar el pod.
  #
  # requests: garantía mínima de recursos (el pod SIEMPRE tiene esto disponible)
  # limits: máximo que puede consumir (si supera limits, el pod es terminado)
  #
  # Para producción, ajustar según carga real usando métricas de Prometheus.
  # ===========================================================================
  set {
    name  = "controller.resources.requests.cpu"
    value = "100m" # 100 milicores = 0.1 CPU core
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "controller.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "controller.resources.limits.memory"
    value = "512Mi"
  }

  # ===========================================================================
  # HORIZONTAL POD AUTOSCALER (HPA) PARA NGINX
  # Escala automáticamente el número de réplicas de NGINX basándose en carga.
  # Complementa al Cluster Autoscaler:
  #   1. HPA escala pods primero.
  #   2. Si no hay nodos para los nuevos pods → Cluster Autoscaler agrega nodos.
  #
  # minReplicas/maxReplicas: límites del HPA.
  # targetCPUUtilizationPercentage: umbral de CPU para escalar.
  # ===========================================================================
  set {
    name  = "controller.autoscaling.enabled"
    value = "true"
  }
  set {
    name  = "controller.autoscaling.minReplicas"
    value = "2"
  }
  set {
    name  = "controller.autoscaling.maxReplicas"
    value = "10"
  }
  set {
    name  = "controller.autoscaling.targetCPUUtilizationPercentage"
    value = "80"
  }

  # ===========================================================================
  # POD DISRUPTION BUDGET (PDB)
  # Garantiza que SIEMPRE haya al menos 1 réplica disponible durante:
  #   - Upgrades del nodo (node drain)
  #   - Upgrades del clúster Kubernetes
  #   - Operaciones de mantenimiento
  #
  # Sin PDB, todos los pods de NGINX podrían ser eliminados simultáneamente
  # durante un upgrade, causando downtime.
  # ===========================================================================
  set {
    name  = "controller.podDisruptionBudget.enabled"
    value = "true"
  }
  set {
    name  = "controller.podDisruptionBudget.minAvailable"
    value = "1"
  }

  # ===========================================================================
  # CLASE DE INGRESS
  # ingressClass = "nginx" → Esta es la clase que usarán los objetos Ingress
  # para indicar que deben ser gestionados por ESTE controller.
  #
  # En un clúster con múltiples Ingress Controllers (nginx, traefik, etc.),
  # la ingressClassName en el objeto Ingress determina cuál controller lo procesa.
  #
  # Ejemplo en un objeto Ingress:
  #   spec:
  #     ingressClassName: nginx   ← Apunta a este controller
  # ===========================================================================
  set {
    name  = "controller.ingressClassResource.name"
    value = "nginx"
  }
  set {
    name  = "controller.ingressClassResource.default"
    value = "true" # Este controller procesa Ingress sin ingressClassName explícita
  }

  # ===========================================================================
  # CONFIGURACIÓN ADICIONAL DEL NGINX
  # use-forwarded-headers: Preserva la IP real del cliente cuando hay proxies.
  # compute-full-forwarded-for: Agrega todas las IPs del chain de proxies.
  # use-proxy-protocol: Para integración con proxies que usan PROXY protocol.
  # ===========================================================================
  set {
    name  = "controller.config.use-forwarded-headers"
    value = "true"
  }
  set {
    name  = "controller.config.compute-full-forwarded-for"
    value = "true"
  }

  # ===========================================================================
  # MÉTRICAS PARA PROMETHEUS
  # Expone métricas de NGINX en formato Prometheus.
  # Útil para dashboards de Grafana y alertas sobre el Ingress Controller.
  # ===========================================================================
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  # ===========================================================================
  # ANOTACIÓN EN EL CONTROLLER SERVICE: externalTrafficPolicy
  # "Local" vs "Cluster":
  #
  # Local:
  #   - El ILB solo reenvía tráfico a nodos que TIENEN el pod de NGINX.
  #   - Preserva la IP de origen del cliente (Source IP preservation).
  #   - RECOMENDADO para ILB interno donde necesitamos saber la IP del cliente.
  #   - Desventaja: Si un nodo sin pod NGINX recibe la solicitud, se descarta.
  #
  # Cluster (default):
  #   - El tráfico puede ir a cualquier nodo y luego se enruta al pod correcto.
  #   - La IP de origen se pierde (SNAT).
  # ===========================================================================
  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }

  # Asegurar que el release depende de que el clúster esté creado
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_role_assignment.aks_network_contributor
  ]
}
