# =============================================================================
# example_ingress.tf
# Ejemplo de uso: despliega una aplicación de prueba y un objeto Ingress
# que usa el NGINX Ingress Controller con el ILB.
#
# Este archivo es OPCIONAL y sirve para:
#   1. Verificar que el Ingress Controller funciona correctamente.
#   2. Mostrar cómo se crean Ingress objects en Kubernetes via Terraform.
#   3. Servir como plantilla para aplicaciones reales.
#
# Para NO desplegarlo en producción, eliminar este archivo o usar:
#   terraform apply -target=helm_release.nginx_ingress
# =============================================================================

# -----------------------------------------------------------------------------
# NAMESPACE PARA LA APLICACIÓN DE EJEMPLO
# Best practice: cada aplicación en su propio namespace para aislamiento.
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "example_app" {
  metadata {
    name = "example-app"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# -----------------------------------------------------------------------------
# DEPLOYMENT: Aplicación de ejemplo (nginx web server básico)
# -----------------------------------------------------------------------------
resource "kubernetes_deployment" "example_app" {
  metadata {
    name      = "example-app"
    namespace = kubernetes_namespace.example_app.metadata[0].name
    labels = {
      app = "example-app"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "example-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "example-app"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:alpine"
          port {
            container_port = 80
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.nginx_ingress]
}

# -----------------------------------------------------------------------------
# SERVICE: Expone la app internamente en el clúster (ClusterIP)
# NOTA: Este Service es de tipo ClusterIP (interno al clúster).
# El tráfico externo llega via ILB → NGINX → este Service → pods.
# -----------------------------------------------------------------------------
resource "kubernetes_service" "example_app" {
  metadata {
    name      = "example-app"
    namespace = kubernetes_namespace.example_app.metadata[0].name
  }

  spec {
    selector = {
      app = "example-app"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

# -----------------------------------------------------------------------------
# INGRESS: Regla de enrutamiento HTTP
#
# Este objeto Ingress le dice al NGINX Ingress Controller cómo enrutar
# el tráfico que llega al ILB.
#
# Flujo completo:
#   Cliente → ILB (10.0.4.10:80) → NGINX Pod → Service "example-app" → Pod
#
# ingressClassName: "nginx" → Este Ingress es procesado por nuestro controller.
# host: "example.internal.empresa.com" → Dominio interno que se resuelve al ILB.
# path: "/" → Enrutar todas las rutas al service example-app.
# pathType: "Prefix" → Coincide con "/" y cualquier subpath (/about, /api, etc.)
#
# Para que funcione, el DNS interno debe resolver:
#   example.internal.empresa.com → 10.0.4.10
# -----------------------------------------------------------------------------
resource "kubernetes_ingress_v1" "example_app" {
  metadata {
    name      = "example-app"
    namespace = kubernetes_namespace.example_app.metadata[0].name
    annotations = {
      # Clase del Ingress Controller que lo procesará
      "kubernetes.io/ingress.class" = "nginx"

      # Reescritura de URL: si la app espera "/" pero el path del Ingress es "/app"
      # "nginx.ingress.kubernetes.io/rewrite-target" = "/"

      # Rate limiting (ejemplo):
      # "nginx.ingress.kubernetes.io/limit-rps" = "10"

      # Tamaño máximo del body (útil para uploads):
      # "nginx.ingress.kubernetes.io/proxy-body-size" = "10m"
    }
  }

  spec {
    # ingressClassName referencia el IngressClass creado por el Helm chart
    ingress_class_name = "nginx"

    rule {
      host = "example.internal.empresa.com"  # Ajustar al dominio interno real

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.example_app.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.nginx_ingress]
}

# Output del Ingress para referencia
output "example_ingress_host" {
  description = "Hostname configurado en el Ingress de ejemplo."
  value       = "http://example.internal.empresa.com (resuelve a ${var.ilb_ip_address})"
}
