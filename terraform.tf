# HTTP-LB
# forwarding-rule-1 -> proxy1 -> urlmap1 -> backend1  -> instance-group -> instance1
#                                                                       -> instance2
#
# TCP-LB
# forwarding-rule-2 -> backend2  -> instance-group -> instance1
#                                                  -> instance2
#
# Error: Error waiting to create RegionBackendService: Error waiting for Creating RegionBackendService: Validation failed for instance group 'projects/pruebas-adri-lb/zones/europe-west1-b/instanceGroups/instance-group-http': backend services 'projects/pruebas-adri-lb/regions/europe-west1/backendServices/backend1' and 'projects/pruebas-adri-lb/regions/europe-west1/backendServices/backend2' point to the same instance group but the backends have incompatible balancing_mode. Values should be the same.
# Error: Error waiting to create RegionBackendService: Error waiting for Creating RegionBackendService: Validation failed for instance group 'projects/pruebas-adri-lb/zones/europe-west1-b/instanceGroups/instance-group-http': backend services 'projects/pruebas-adri-lb/regions/europe-west1/backendServices/backend1' and 'projects/pruebas-adri-lb/regions/europe-west1/backendServices/backend2' point to the same instance group but the backends have incompatible balancing_mode. Values should be the same.

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

locals {
  project_name = "pruebas-adri-lb"
  region       = "europe-west1"
  zone         = "europe-west1-b"
  image        = "rocky-linux-9-optimized-gcp"
}

provider "google" {
  project = local.project_name
  region  = local.region
  zone    = local.zone
}

provider "google-beta" {
  project = local.project_name
  region  = local.region
  zone    = local.zone
}

resource "google_compute_instance" "instance1" {
  name         = "instance1"
  machine_type = "e2-micro"
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = local.image
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }
}

resource "google_compute_instance_group" "instance-group" {
  name        = "instance-group-http"
  zone        = local.zone

  instances = [
    google_compute_instance.instance1.self_link,
    google_compute_instance.instance2.self_link,
  ]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_instance" "instance2" {
  name         = "instance2"
  machine_type = "e2-micro"
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = local.image
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }
}


resource "google_compute_firewall" "allow-all" {
  name    = "allow-all"
  network = "default"
  allow {
    protocol = "all"
  }
  source_ranges = ["0.0.0.0/0"]
}


# ILB 1 - default groups
resource "google_compute_subnetwork" "proxy-only" {
  name          = "proxy-only"
  ip_cidr_range = "10.20.30.0/24"
  purpose       = "INTERNAL_HTTPS_LOAD_BALANCER"
  role          = "ACTIVE"
  network       = "default"
}

resource "google_compute_forwarding_rule" "forwarding-rule-1" {
  name                  = "forwarding-rule-1"
  region                = local.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  target                = google_compute_region_target_http_proxy.proxy1.id
  port_range            = 80
}

resource "google_compute_region_target_http_proxy" "proxy1" {
  name    = "proxy1"
  url_map = google_compute_region_url_map.urlmap1.id
}

resource "google_compute_region_url_map" "urlmap1" {
  region = local.region
  name   = "urlmap1"

  default_service = google_compute_region_backend_service.backend1.id
}

resource "google_compute_health_check" "http" {
  provider = google-beta
  name     = "http"

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

resource "google_compute_region_backend_service" "backend1" {
  name                  = "backend1"
  region                = local.region
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "INTERNAL_MANAGED"
  backend {
    group           = google_compute_instance_group.instance-group.self_link
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  health_checks = [google_compute_health_check.http.self_link]
}


# ILB 2 - default-tcp groups
resource "google_compute_forwarding_rule" "forwarding-rule-2" {
  name                  = "forwarding-rule-2"
  region                = local.region
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.backend2.self_link
  ports = ["1000"]
}

resource "google_compute_region_backend_service" "backend2" {
  name                  = "backend2"
  region                = local.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  backend {
    group          = google_compute_instance_group.instance-group.id
    balancing_mode = "CONNECTION"
  }
  health_checks = [google_compute_region_health_check.tcp-1000.self_link]
}

resource "google_compute_region_health_check" "tcp-1000" {
  provider = google-beta
  name     = "tcp-1000"

  tcp_health_check {
    port = "1000"
  }
}
