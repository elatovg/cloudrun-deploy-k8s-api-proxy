resource "google_compute_instance" "gce-instance" {
  name         = local.vm_name
  machine_type = "e2-medium"
  zone         = local.zone
  project      = local.project

  boot_disk {
    initialize_params {
      image = local.vm_image
    }
  }

  network_interface {
    network            = local.vpc_name
    subnetwork         = local.vpc_subnet
    subnetwork_project = local.project
  }

  metadata = {
    kubectl_location    = "gs://bucket/kubectl-1.22"
    source_archive      = "gs://bucket/cloudrun-deploy-k8s-api-proxy.tar.gz"
    k8s_api_proxy_image = "${local.artifact_registry_region}-docker.pkg.dev/${local.project}/${local.artifact_registry_repo_name}/${local.k8s_api_proxy_image_name}"
    gke_cluster_name    = local.gke_cluster_name
    gke_zone            = "${local.region}-c"
  }

  # metadata_startup_script = "echo hi > /test.txt"
  metadata_startup_script = file("setup-gce.bash")

  service_account {
    email  = google_service_account.gce_service_account.email
    scopes = ["cloud-platform", "userinfo-email"]
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes to metadata, since ansible will add new values
      metadata,
    ]
  }
}