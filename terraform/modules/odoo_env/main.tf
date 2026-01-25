locals {
  name_prefix = "${var.client}-${var.env}"

  # DB settings (simple & deterministic)
  db_name = "odoo"
  db_user = "odoo"
  db_pass = "odoo-${var.client}-${var.env}-pass"

  tls_secret_name = "${local.name_prefix}-tls"
  db_secret_name  = "${local.name_prefix}-db"

  db_service_name   = "${local.name_prefix}-db"
  odoo_service_name = "${local.name_prefix}-odoo"
}

# TLS (self-signed)
resource "tls_private_key" "tls" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "tls" {
  private_key_pem = tls_private_key.tls.private_key_pem

  subject {
    common_name  = var.host
    organization = "local"
  }

  validity_period_hours = 8760
  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]

  dns_names = [var.host]
}

resource "kubernetes_secret_v1" "tls" {
  metadata {
    name      = local.tls_secret_name
    namespace = var.namespace
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_self_signed_cert.tls.cert_pem
    "tls.key" = tls_private_key.tls.private_key_pem
  }
}

# DB credentials secret
resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = local.db_secret_name
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    POSTGRES_DB       = local.db_name
    POSTGRES_USER     = local.db_user
    POSTGRES_PASSWORD = local.db_pass
  }
}

# Postgres service
resource "kubernetes_service_v1" "db" {
  metadata {
    name      = local.db_service_name
    namespace = var.namespace
    labels = {
      app = local.db_service_name
    }
  }

  spec {
    selector = {
      app = local.db_service_name
    }

    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# Postgres statefulset
resource "kubernetes_stateful_set_v1" "db" {
  metadata {
    name      = local.db_service_name
    namespace = var.namespace
    labels = {
      app = local.db_service_name
    }
  }

  spec {
    service_name = kubernetes_service_v1.db.metadata[0].name
    replicas     = 1

    selector {
      match_labels = {
        app = local.db_service_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.db_service_name
        }
      }

      spec {
        container {
          name  = "postgres"
          image = var.postgres_image

          port {
            container_port = 5432
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.db.metadata[0].name
            }
          }

          # Simple ephemeral storage
          volume_mount {
            name       = "pgdata"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "pgdata"
          empty_dir {}
        }
      }
    }
  }
}

# Odoo service
resource "kubernetes_service_v1" "odoo" {
  metadata {
    name      = local.odoo_service_name
    namespace = var.namespace
    labels = {
      app = local.odoo_service_name
    }
  }

  spec {
    selector = {
      app = local.odoo_service_name
    }

    port {
      port        = var.odoo_port
      target_port = var.odoo_port
    }
  }
}

# Explicit Odoo ConfigMap (forces DB host, avoids "db" fallback)
resource "kubernetes_config_map_v1" "odoo_conf" {
  metadata {
    name      = "${local.name_prefix}-odoo-conf"
    namespace = var.namespace
  }

  data = {
  "odoo.conf" = <<-EOF
[options]
db_host = ${kubernetes_service_v1.db.metadata[0].name}
db_port = 5432
db_user = ${local.db_user}
db_password = ${local.db_pass}

; IMPORTANT: make Odoo respect X-Forwarded-* headers from ingress
proxy_mode = True
EOF
  }
}

# Init Job per env
resource "kubernetes_job_v1" "odoo_init" {
  metadata {
    name      = "${local.name_prefix}-odoo-init"
    namespace = var.namespace
    labels = {
      app = "${local.name_prefix}-odoo-init"
    }
  }

  spec {
    backoff_limit = 6

    template {
      metadata {
        labels = {
          app = "${local.name_prefix}-odoo-init"
        }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "odoo-init"
          image = var.odoo_image

          volume_mount {
            name       = "odoo-conf"
            mount_path = "/etc/odoo/odoo.conf"
            sub_path   = "odoo.conf"
            read_only  = true
          }

          # Initialises schema then exits successfully
            args = [
                "-c", "/etc/odoo/odoo.conf",
                "-d", local.db_name,
                "-i", "base",
                "--without-demo=all",
                "--stop-after-init",
            ]
        }

        volume {
          name = "odoo-conf"
          config_map {
            name = kubernetes_config_map_v1.odoo_conf.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_stateful_set_v1.db]
}

# Odoo deployment
resource "kubernetes_deployment_v1" "odoo" {
  metadata {
    name      = local.odoo_service_name
    namespace = var.namespace
    labels = {
      app = local.odoo_service_name
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.odoo_service_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.odoo_service_name
        }
      }

      spec {
        container {
          name  = "odoo"
          image = var.odoo_image

          port {
            container_port = var.odoo_port
          }

          # Mounts the explicit config as /etc/odoo/odoo.conf
          volume_mount {
            name       = "odoo-conf"
            mount_path = "/etc/odoo/odoo.conf"
            sub_path   = "odoo.conf"
            read_only  = true
          }

          # Forces Odoo to use as config & initialises DB
          args = [
            "-c", "/etc/odoo/odoo.conf",
            "-d", local.db_name,
            "--without-demo=all",
          ]
        }

        volume {
          name = "odoo-conf"
          config_map {
            name = kubernetes_config_map_v1.odoo_conf.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_job_v1.odoo_init]
}

# Ingress (HTTPS only)
resource "kubernetes_ingress_v1" "odoo" {
  metadata {
    name      = "${local.odoo_service_name}-ing"
    namespace = var.namespace
    annotations = {
        "nginx.ingress.kubernetes.io/ssl-redirect" = "true"

        # For Odoo (long requests / exports)
        "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
        "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
        "nginx.ingress.kubernetes.io/proxy-body-size"    = "64m"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [var.host]
      secret_name = kubernetes_secret_v1.tls.metadata[0].name
    }

    rule {
      host = var.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.odoo.metadata[0].name
              port {
                number = var.odoo_port
              }
            }
          }
        }
      }
    }
  }
}
