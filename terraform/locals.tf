locals {
  project                     = "project"
  region                      = "us-central1"
  vm_image                    = "ubuntu-os-cloud/ubuntu-2004-lts"
  vm_name                     = "test-vm"
  zone                        = "${local.region}-c"
  vpc_name                    = "spoke"
  vpc_subnet                  = local.region
  artifact_registry_region    = local.region
  artifact_registry_repo_name = "tools"
  k8s_api_proxy_image_name    = "k8s-api-proxy"
  gke_cluster_name            = "private-cluster"
  gke_zone                    = "${local.region}-c"
  gce_roles = [
    "roles/storage.admin",
    "roles/logging.logWriter",
    "roles/logging.viewer",
    "roles/cloudbuild.builds.editor",
    "roles/container.developer",
    # "roles/storage.legacyBucketReader"
    # For metadata modification
    "roles/compute.instanceAdmin.v1",
    "roles/iam.serviceAccountUser"
  ]
  build_roles = [
    "roles/storage.admin",
    "roles/artifactregistry.writer"
  ]
}