locals {
  controllers = ["controller-0","controller-1","controller-2"]
  workers     = ["worker-0","worker-1","worker-2"]
  region      = "us-west1"
  zone        = "us-west1-c"
}


provider "google" {
  credentials = file("account.json")
  project     = "schuyler-bishop-contino"
  region      = local.region
  zone        = local.zone
}

resource "google_compute_network" "network-kubernetes-the-hard-way" {
  name = "kubernetes-the-hard-way"
  auto_create_subnetworks = false
}

resource "google_compute_route" "route-kubernetes-route" {
  count       = 3
  name        = "kubernetes-route-10-200-${count.index}-0-24"
  dest_range  = "10.200.${count.index}.0/24"
  network     = google_compute_network.network-kubernetes-the-hard-way.self_link
  next_hop_ip = "10.240.0.2${count.index}"
}

resource "google_compute_subnetwork" "subnet-kubernetes-the-hard-way" {
  name          = "kubernetes-the-hard-way"
  ip_cidr_range = "10.240.0.0/24"
  region        = local.region
  network       = google_compute_network.network-kubernetes-the-hard-way.name
}

resource "google_compute_firewall" "fwrule-kubernetes-the-hard-way-allow-internal" {
  name    = "kubernetes-the-hard-way-allow-internal"
  network = google_compute_network.network-kubernetes-the-hard-way.name
  source_ranges = ["10.240.0.0/24","10.200.0.0/16"]

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "udp"
  }

  allow {
    protocol = "tcp"
  }
}

resource "google_compute_firewall" "fwrule-kubernetes-the-hard-way-allow-external" {
  name    = "kubernetes-the-hard-way-allow-external"
  network = google_compute_network.network-kubernetes-the-hard-way.name
  allow {
    protocol = "tcp"
    ports = ["22","6443"]
  }
}

resource "google_compute_address" "address-kubernetes-the-hard-way" {
  name         = "kubernetes-the-hard-way"
  region       = local.region
}

resource "google_compute_http_health_check" "health_check_kubernetes" {
  name         = "kubernetes"
  description  = "Kubernetes Health Check"
  request_path = "/healthz"
  host         = "kubernetes.default.svc.cluster.local"
}

resource "google_compute_target_pool" "pool_kubernetes_target_pool" {
  name = "kubernetes-target-pool"

  instances   = [ for s in local.controllers : "${local.zone}/${s}" ]

  health_checks = [
    google_compute_http_health_check.health_check_kubernetes.name,
  ]
}

resource "google_compute_firewall" "fwrule_kubernetes_the_hard_way_allow_health_check" {
  name    = "kubernetes-the-hard-way-allow-health-check"
  network = google_compute_network.network-kubernetes-the-hard-way.self_link
  source_ranges = ["209.85.152.0/22","209.85.204.0/22","35.191.0.0/16"]
  allow {
    protocol = "tcp"
  }
}

resource "google_compute_forwarding_rule" "fwrule_kubernetes_forwarding_rule" {
  name       = "kubernetes-forwarding-rule"
  target     = google_compute_target_pool.pool_kubernetes_target_pool.self_link
  ip_address = google_compute_address.address-kubernetes-the-hard-way.address
  port_range = "6443"
  region     = local.region
}

resource "google_compute_instance" "instance-controller" {
  count        = length(local.controllers)
  name         = "controller-${count.index}"
  machine_type = "n1-standard-1"
  zone         = local.zone
  can_ip_forward = true

  tags = ["kubernetes-the-hard-way","controller"]

  boot_disk {
    initialize_params {
      size = 200
      image = "ubuntu-os-cloud/ubuntu-1804-lts"
    }
  }

  network_interface {
    network_ip = "10.240.0.1${count.index}"
    subnetwork = google_compute_subnetwork.subnet-kubernetes-the-hard-way.self_link

    access_config {
      // Ephemeral IP
    }
  }

  service_account {
    scopes = ["compute-rw","storage-ro","service-management","service-control","logging-write","monitoring"]
  }
}

resource "google_compute_instance" "instance-worker" {
  count        = length(local.workers)
  name         = "worker-${count.index}"
  machine_type = "n1-standard-1"
  zone         = local.zone
  can_ip_forward = true

  tags = ["kubernetes-the-hard-way","worker"]

  boot_disk {
    initialize_params {
      size = 200
      image = "ubuntu-os-cloud/ubuntu-1804-lts"
    }
  }

  network_interface {
    network_ip = "10.240.0.2${count.index}"
    subnetwork = google_compute_subnetwork.subnet-kubernetes-the-hard-way.self_link

    access_config {
      // Ephemeral IP
    }
  }

  service_account {
    scopes = ["compute-rw","storage-ro","service-management","service-control","logging-write","monitoring"]
  }

  metadata = {
    pod-cidr = "10.200.${count.index}.0/24"
  }
}
