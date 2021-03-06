resource "kubernetes_deployment" "gitlfs" {
  metadata {
    name      = "gitlfs"
    namespace = "${kubernetes_namespace.gitlfs.metadata.0.name}"

    labels {
      name = "gitlfs"
      app  = "gitlfs"
    }
  }

  spec {
    replicas = "${var.replicas}"

    selector {
      name = "gitlfs"
      app  = "gitlfs"
    }

    strategy {
      type = "RollingUpdate"

      rolling_update {
        max_surge       = "${ceil(var.replicas * 1.5)}"
        max_unavailable = "${floor(var.replicas * 0.5)}"
      }
    }

    template {
      metadata {
        labels {
          name = "gitlfs"
          app  = "gitlfs"
        }
      }

      spec {
        container {
          name              = "gitlfs"
          image             = "${var.gitlfs_image}"
          image_pull_policy = "Always"

          port {
            name           = "gitlfs"
            container_port = 80
          }

          # https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container
          resources {
            limits {
              cpu    = "0.5"
              memory = "512Mi"
            }

            requests {
              cpu    = "0.25"
              memory = "256Mi"
            }
          }

          # https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/
          liveness_probe {
            http_get {
              path = "/"
              port = "80"
            }

            initial_delay_seconds = "30"
            timeout_seconds       = "5"
            period_seconds        = "10"
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "80"
            }

            initial_delay_seconds = "1"
            timeout_seconds       = "2"
            period_seconds        = "10"
          }

          env {
            name = "AWS_ACCESS_KEY_ID"

            value_from {
              secret_key_ref {
                name = "gitlfs"
                key  = "AWS_ACCESS_KEY_ID"
              }
            }
          }

          env {
            name = "AWS_SECRET_ACCESS_KEY"

            value_from {
              secret_key_ref {
                name = "gitlfs"
                key  = "AWS_SECRET_ACCESS_KEY"
              }
            }
          }

          env {
            name = "AWS_REGION"

            value_from {
              secret_key_ref {
                name = "gitlfs"
                key  = "AWS_REGION"
              }
            }
          }

          env {
            name = "S3_BUCKET"

            value_from {
              secret_key_ref {
                name = "gitlfs"
                key  = "S3_BUCKET"
              }
            }
          }

          env {
            name = "LFS_SERVER_URL"

            value_from {
              secret_key_ref {
                name = "gitlfs"
                key  = "LFS_SERVER_URL"
              }
            }
          }

          env {
            name  = "LFS_REDIS_HOST"
            value = "$(REDIS_MASTER_SERVICE_HOST)"
          }

          env {
            name  = "LFS_REDIS_PORT"
            value = "$(REDIS_MASTER_SERVICE_PORT)"
          }

          env {
            name  = "LFS_GITHUB_ORG"
            value = "${var.github_org}"
          }

          volume_mount {
            name       = "nginx-logs"
            mount_path = "/var/log/nginx"
          }
        } # container

        # https://kubernetes.io/docs/concepts/cluster-administration/logging/#streaming-sidecar-container
        container {
          name  = "gitlfs-nginx-access"
          image = "busybox"
          args  = ["/bin/sh", "-c", "tail -n+1 -f /var/log/nginx/access.log"]

          volume_mount {
            name       = "nginx-logs"
            mount_path = "/var/log/nginx"
          }
        } # container

        container {
          name  = "gitlfs-nginx-error"
          image = "busybox"
          args  = ["/bin/sh", "-c", "tail -n+1 -f /var/log/nginx/error.log"]

          volume_mount {
            name       = "nginx-logs"
            mount_path = "/var/log/nginx"
          }
        } # container

        volume {
          name      = "nginx-logs"
          empty_dir = {}
        }
      } # spec
    } # template
  } # spec

  depends_on = [
    # attempt to avoid startup crashes due to missing env vars
    "kubernetes_secret.gitlfs",

    # ensure that REDIS_* env vars are present
    "helm_release.redis",

    # not strictly required as this dep is implicit via
    # kubernetes_secret.gitlfs, this is essentially a reminder that this dep
    # exists
    "aws_s3_bucket.lfs_objects",
  ]
}
