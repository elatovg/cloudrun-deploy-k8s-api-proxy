data "google_project" "project" {
  project_id = local.project
}
resource "google_service_account" "gce_service_account" {
  project      = local.project
  account_id   = "gce-sa"
  display_name = "GCE Service Account"
}

resource "google_project_iam_member" "iam-policy-compute-sa" {
  for_each = toset(local.gce_roles)
  project  = local.project
  role     = each.key
  member   = "serviceAccount:${google_service_account.gce_service_account.email}"
}

resource "google_project_iam_member" "iam-policy-build-sa" {
  for_each = toset(local.build_roles)
  project  = local.project
  role     = each.key
  member   = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}