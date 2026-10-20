job "caddy" {
  type = "service"

  group "caddy" {
    network {
      port "http" {
        to = 8080
      }
    }

    task "caddy" {
      driver         = "docker"
      shutdown_delay = "5s"

      config {
        image   = "caddy:2.10"
        ports   = ["http"]
        command = "caddy"
        args    = ["run", "--config", "/local/Caddyfile", "--adapter", "caddyfile"]
      }

      # Metrics must be enabled globally, then exposed on a custom path
      template {
        destination = "local/Caddyfile"
        data        = <<-EOF
          {
            metrics
          }

          :8080 {
            handle /stats/prometheus {
              metrics
            }
            handle {
              respond "Hello from Caddy (allocation {{ env "NOMAD_ALLOC_ID" }})"
            }
          }
        EOF
      }

      resources {
        cpu    = 100
        memory = 64
      }

      service {
        name     = "caddy"
        port     = "http"
        provider = "nomad"
        tags     = ["prometheus-metrics", "metrics-path=/stats/prometheus"]

        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}