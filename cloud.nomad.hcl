# dropicture/cloud.nomad.hcl
locals {
  image_base = "ghcr.io/redjem-amir/dropicture.com"
}

variable "app_version" {
  type = string
}

variable "postgres_host" {
  type = string
}

variable "postgres_db" {
  type = string
}

variable "postgres_user" {
  type = string
}

variable "postgres_password" {
  type = string
}

variable "redis_host" {
  type = string
}

job "dropicture" {
  datacenters = ["dc1"]
  type        = "service"

  group "db" {
    network {
      port "postgres" {
        static = 5432
        to     = 5432
      }
    }

    volume "postgres-data" {
      type      = "host"
      source    = "postgres-data"
      read_only = false
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "app-db" {
      driver = "docker"

      config {
        image    = "postgres:18.3"
        ports    = ["postgres"]
        shm_size = 268435456
      }

      volume_mount {
        volume      = "postgres-data"
        destination = "/var/lib/postgresql"
      }

      env {
        POSTGRES_DB       = var.postgres_db
        POSTGRES_USER     = var.postgres_user
        POSTGRES_PASSWORD = var.postgres_password
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      service {
        name     = "app-db"
        provider = "nomad"
        port     = "postgres"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "5s"
        }
      }
    }
  }

  group "cache" {
    network {
      port "redis" {
        static = 6379
        to     = 6379
      }
    }

    volume "dragonfly-data" {
      type      = "host"
      source    = "dragonfly-data"
      read_only = false
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "app-dragonfly" {
      driver = "docker"

      config {
        image = "ghcr.io/dragonflydb/dragonfly:v1.38.1"
        ports = ["redis"]
        args  = ["--default_lua_flags=allow-undeclared-keys"]

        ulimit {
          memlock = "-1"
        }
      }

      volume_mount {
        volume      = "dragonfly-data"
        destination = "/data"
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      service {
        name     = "app-dragonfly"
        provider = "nomad"
        port     = "redis"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "5s"
        }
      }
    }
  }

  group "backend" {
    network {
      port "http" {
        static = 3001
        to     = 3001
      }
    }

    update {
      max_parallel     = 1
      min_healthy_time = "10s"
      healthy_deadline = "5m"
      auto_revert      = true
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "app-backend" {
      driver = "docker"

      config {
        image = "${local.image_base}/backend:${var.app_version}"
        ports = ["http"]
      }

      env {
        NODE_ENV          = "production"
        POSTGRES_HOST     = var.postgres_host
        POSTGRES_DB       = var.postgres_db
        POSTGRES_USER     = var.postgres_user
        POSTGRES_PASSWORD = var.postgres_password
        REDIS_HOST        = var.redis_host
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name     = "app-backend"
        provider = "nomad"
        port     = "http"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "5s"
        }
      }
    }
  }

  group "frontend" {
    network {
      port "http" {
        static = 3000
        to     = 3000
      }
    }

    update {
      max_parallel     = 1
      min_healthy_time = "10s"
      healthy_deadline = "5m"
      auto_revert      = true
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "app-frontend" {
      driver = "docker"

      config {
        image = "${local.image_base}/frontend:${var.app_version}"
        ports = ["http"]
      }

      env {
        NODE_ENV = "production"
        PORT     = "${NOMAD_PORT_http}"
        HOSTNAME = "0.0.0.0"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name     = "app-frontend"
        provider = "nomad"
        port     = "http"

        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "5s"
        }
      }
    }
  }

  group "proxy" {
    network {
      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
    }

    volume "tls-origin" {
      type      = "host"
      source    = "tls-origin"
      read_only = true
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "caddy" {
      driver = "docker"

      config {
        image        = "caddy:2"
        network_mode = "host"
        command      = "caddy"
        args         = ["run", "--config", "/local/Caddyfile", "--adapter", "caddyfile"]
      }

      volume_mount {
        volume      = "tls-origin"
        destination = "/tls"
      }
      template {
        destination = "local/Caddyfile"
        data        = <<EOH
dropicture.com, www.dropicture.com {
	tls /tls/origin.crt /tls/origin.key

	handle /api/* {
		reverse_proxy 127.0.0.1:3001
	}

	handle {
		reverse_proxy 127.0.0.1:3000
	}
}
EOH
      }

      resources {
        cpu    = 200
        memory = 128
      }

      service {
        name     = "proxy"
        provider = "nomad"
        port     = "https"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "5s"
        }
      }
    }
  }
}