locals {
  project_id = "project"
  sa         = "terraf@${local.project_id}.iam.gserviceaccount.com"
  apis = [
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
  roles = [
    "roles/iam.serviceAccountUser",
    "roles/iam.serviceAccountAdmin",
    "roles/compute.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/artifactregistry.admin"
  ]
}

resource "google_project_service" "gcp_services" {
  for_each                   = toset(local.apis)
  project                    = local.project_id
  service                    = each.key
  disable_dependent_services = true
}

resource "google_project_iam_member" "iam-policy-user" {
  for_each = toset(local.roles)
  project  = local.project_id
  role     = each.key
  member   = "serviceAccount:${local.sa}"
}