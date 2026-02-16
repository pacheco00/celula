############################
# 4_03_appgw.tf
############################

# Public IP del AppGW (para FQDN que usará APIM como backend)
resource "azurerm_public_ip" "appgw_pip" {
  name                = "${var.prefix}-appgw-pip-${var.env}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"

  # Debe ser único globalmente; ajusta si colisiona
  domain_name_label = "${var.prefix}-${var.env}-appgw"

  tags = {
    project     = var.prefix
    environment = var.env
  }
}

# Intentar descubrir la IP del ILB del Ingress
data "kubernetes_service" "ingress_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  #depends_on = [helm_release.ingress_nginx]
}
# Application Gateway (WAF_v2) - HTTP/80 (sin certificado)

resource "azurerm_application_gateway" "appgw" {
  name                = "${var.prefix}-appgw-${var.env}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appgw-ipcfg"
    subnet_id = azurerm_subnet.snet_appgw.id
  }
  frontend_port {
    name = "port-80"
    port = 80
  }
  frontend_port {
    name = "port_31080"
    port = 31080
  }

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  # política TLS soportada
  ssl_policy {
    policy_type          = "Predefined"
    policy_name          = "AppGwSslPolicy20220101S" # o "AppGwSslPolicy20220101"
    min_protocol_version = "TLSv1_2"
  }

  #  backend_http_settings 
  backend_http_settings {
    name                                = "http-settings-80"
    port                                = 31080
    protocol                            = "Http"
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    pick_host_name_from_backend_address = false
    probe_name                          = "healthprobetcslab"
  }
  backend_http_settings {
    name                                = "http-setting-ingress"
    port                                = 80
    protocol                            = "Http"
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 20
    pick_host_name_from_backend_address = false
    probe_name                          = "healthprobe-ingress"
  }

  backend_address_pool {
    name         = "pool-ingress"
    ip_addresses = ["10.40.1.62"]
  }
  backend_address_pool {
    name         = "pool-nodeport"
    ip_addresses = ["10.40.1.39"]
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }
  http_listener {
    name                           = "listener-nodeport"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "port_31080"
    protocol                       = "Http"
  }
  request_routing_rule {
    name      = "rule-http-to-ingress"
    rule_type = "Basic"

    http_listener_name         = "http-listener"
    backend_address_pool_name  = "pool-ingress"
    backend_http_settings_name = "http-setting-ingress"


    priority = 98
  }
  request_routing_rule {
    name      = "rule-nodeport"
    rule_type = "Basic"

    http_listener_name         = "listener-nodeport"
    backend_address_pool_name  = "pool-nodeport"
    backend_http_settings_name = "http-settings-80"


    priority = 99 # <-- OBLIGATORIO desde api-version 2021-08-01
  }
  probe {
    host                                      = "10.40.1.39"
    interval                                  = 30
    minimum_servers                           = 0
    name                                      = "healthprobetcslab"
    path                                      = "/healthz"
    pick_host_name_from_backend_http_settings = false
    protocol                                  = "Http"
    timeout                                   = 30
    unhealthy_threshold                       = 3
    match {
      status_code = ["200-399"]
    }
  }
  probe {
    host                                      = "10.40.1.62"
    interval                                  = 30
    minimum_servers                           = 0
    name                                      = "healthprobe-ingress"
    path                                      = "/healthz"
    pick_host_name_from_backend_http_settings = false
    protocol                                  = "Http"
    timeout                                   = 30
    unhealthy_threshold                       = 3
    match {
      status_code = ["200-399"]
    }
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Detection"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }

  tags = {
    project     = var.prefix
    environment = var.env
  }

  depends_on = [azurerm_subnet.snet_appgw]
}

# ===== Outputs =====
output "appgw_public_fqdn" {
  value       = azurerm_public_ip.appgw_pip.fqdn
  description = "FQDN público del App Gateway (backend para APIM)."
}

