#!/bin/bash
## GLOBALS
if [ -f /etc/debian_version ]; then
  DISTRO='Debian'
elif [ -f /etc/redhat-release ]; then
  DISTRO='Redhat'
fi

## BINS
if [ "${DISTRO}" == "Debian" ]; then
  CHMOD="/usr/bin/chmod"
  GCLOUD="/snap/bin/gcloud"
  GSUTIL="/snap/bin/gsutil"
  CURL="/usr/bin/curl"
  CUT="/usr/bin/cut"
  CAT="/usr/bin/cat"
  TAR="/usr/bin/tar"
  BASENAME="/usr/bin/basename"
  # DIRNAME="/usr/bin/dirname"
fi

## CONFIGS
IMAGE_BUILD_ENABLED="true"
KCTL_DEST="/usr/local/bin/kubectl"
VM_NAME=$(${CURL} -H Metadata-Flavor:Google \
  http://metadata/computeMetadata/v1/instance/hostname | ${CUT} -d. -f1)
VM_ZONE=$(${CURL} -H Metadata-Flavor:Google \
  http://metadata/computeMetadata/v1/instance/zone | ${CUT} -d/ -f4)
if [ "${DISTRO}" == "Debian" ]; then
  APT="/bin/apt"
fi

function install_pkg() {
  local pkg_name=$1
  if [ "${DISTRO}" == "Debian" ]; then
    ${APT} install "${pkg_name}" -y
  fi

}

function get_kubectl() {
  kctl_loc=$(${CURL} -H Metadata-Flavor:Google \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/kubectl_location)

  if ! ${GSUTIL} cp "${kctl_loc}" ${KCTL_DEST}; then
    echo "${GSUTIL} cp failed, quitting"
    exit 1
  fi
  ${CHMOD} +x ${KCTL_DEST}
}

function get_kubeconfig() {
  gke_cluster_name=$(${CURL} -H Metadata-Flavor:Google \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/gke_cluster_name)
  gke_zone=$(${CURL} -H Metadata-Flavor:Google \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/gke_zone)
  export HOME="/root"
  if ! ${GCLOUD} container clusters get-credentials "${gke_cluster_name}" \
    --zone "${gke_zone}"; then
    echo "${GCLOUD} container clusters get-credentials failed, quitting"
    exit 1
  fi
}

function deploy_k8s_api_proxy() {
  k8s_api_proxy_image=$(${CURL} -H Metadata-Flavor:Google \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/k8s_api_proxy_image)
  ${CAT} >deploy.yaml <<EOL
apiVersion: apps/v1
kind: Deployment
metadata:
  name: k8s-api-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: k8s-api-proxy
  template:
    metadata:
      labels:
        app: k8s-api-proxy
    spec:
      containers:
      - name: k8s-api-proxy
        image: ${k8s_api_proxy_image}
        ports:
          - containerPort: 8118
EOL

  ${CAT} >svc.yaml <<EOL
apiVersion: v1
kind: Service
metadata:
  labels:
    app: k8s-api-proxy
  name: k8s-api-proxy
  namespace: default
  annotations:
    cloud.google.com/load-balancer-type: "Internal"
spec:
  ports:
  - port: 8118
    protocol: TCP
    targetPort: 8118
  selector:
    app: k8s-api-proxy
  type: LoadBalancer
EOL
  if ! ${KCTL_DEST} apply -f deploy.yaml; then
    echo "${KCTL_DEST} apply -f deploy.yaml failed, quitting"
    return 1
  fi

  if ! ${KCTL_DEST} apply -f svc.yaml; then
    echo "${KCTL_DEST} apply -f svc.yaml failed, quitting"
    return 1
  fi
  return 0
}

function build_image() {
  source_archive=$(${CURL} -H Metadata-Flavor:Google \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/source_archive)
  file_name=$(${BASENAME} "${source_archive}")
  dir_name=$(${BASENAME} "${file_name}" ".tar.gz")
  # gcs_base_dir=$(${DIRNAME} "${source_archive}")
  # gcs_log_dir="${gcs_base_dir}/build_logs"
  ${GSUTIL} cp "${source_archive}" /tmp
  ${TAR} xzf "/tmp/${file_name}" -C /tmp

  ${GCLOUD} builds submit "/tmp/${dir_name}" \
    --config "/tmp/${dir_name}/cloudbuild-proxy.yaml" \
    --async
  build_status=$(${GCLOUD} builds list --limit 1 --format "value(status)")
  pat="(WORKING|QUEUED)"
  until [[ ! ${build_status} =~ ${pat} ]]; do
    sleep 5
    build_status=$(${GCLOUD} builds list --limit 1 --format "value(status)")
  done
  if [[ ${build_status} != "SUCCESS" ]]; then
    echo "${GCLOUD} builds submit failed, quitting"
    exit 1
  fi

}

function main() {
  bootstrapped=$(${CURL} -H Metadata-Flavor:Google \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/bootstrapped)
  if [[ ${bootstrapped} == "true" ]]; then
    echo "Machine is already bootstrapped, skipping startup script"
  else
    if [[ ${IMAGE_BUILD_ENABLED} == "true" ]]; then
      build_image
    fi
    get_kubectl
    get_kubeconfig
    if ! deploy_k8s_api_proxy; then
      echo "bootstrapped failed, not rebooting for troubleshooting"
    else
      echo "bootstrapped succeeed, adding metadata"
      ${GCLOUD} compute instances add-metadata "${VM_NAME}" \
        --zone "${VM_ZONE}" --metadata bootstrapped=true
    fi
  fi
}

main
