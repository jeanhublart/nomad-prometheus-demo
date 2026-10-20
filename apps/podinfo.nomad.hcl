job "podinfo" {
  type = "service"

  group "podinfo" {
    count = 2 # 2 instances = 2 discovered targets

    network {
      port "http" {
        to = 9898 # dynamic host port picked by Nomad
      }
    }

    task "podinfo" {
      driver         = "docker"
      shutdown_delay = "5s"

      config {
        image = "ghcr.io/stefanprodan/podinfo:6.7.1"
        ports = ["http"]
      }

      env {
        PODINFO_UI_MESSAGE = "Deployed by Nomad, scraped automatically"
      }

      resources {
        cpu    = 100
        memory = 64
      }

      service {
        name     = "podinfo"
        port     = "http"
        provider = "nomad"
        tags     = ["prometheus-metrics"] # default /metrics path

        check {
          type     = "http"
          path     = "/healthz"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}