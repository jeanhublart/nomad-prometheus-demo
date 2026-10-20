job "prometheus" {
  type = "service"

  group "monitoring" {
    network {
      port "http" {
        static = 9090
        to     = 9090
      }
    }

    task "prometheus" {
      driver         = "docker"
      shutdown_delay = "5s" # deregister the service before stopping the task

      config {
        image = "prom/prometheus:v3.13.1"
        ports = ["http"]
        args  = ["--config.file=/local/prometheus.yml"]
      }

      # Prometheus config (run.sh runs this job from its own directory so file() resolves)
      template {
        data        = file("prometheus.yml")
        destination = "local/prometheus.yml"
      }

      # Service discovery token, read from the Nomad Variable created by run.sh.
      # The job can read nomad/jobs/prometheus through its workload identity.
      template {
        data        = "{{ with nomadVar \"nomad/jobs/prometheus\" }}{{ .sd_token }}{{ end }}"
        destination = "secrets/nomad_token"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name     = "prometheus"
        port     = "http"
        provider = "nomad"
        tags     = ["prometheus-metrics"] # Prometheus discovers itself

        check {
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}