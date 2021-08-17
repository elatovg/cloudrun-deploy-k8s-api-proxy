resource "google_artifact_registry_repository" "ar-tools" {
  provider = google-beta

  project       = local.project
  location      = local.artifact_registry_region
  repository_id = local.artifact_registry_repo_name
  format        = "DOCKER"
}