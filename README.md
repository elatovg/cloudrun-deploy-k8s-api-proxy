# cloudrun-deploy-k8s-api-proxy

## confirm your base images exist
GCR [Mirrors dockerhub](https://cloud.google.com/container-registry/docs/pulling-cached-images)

```bash
> gcloud container images list --repository=mirror.gcr.io/library | grep alpine
mirror.gcr.io/library/alpine
```

Also list the tags to see which one you want to build from (for example):

```bash
gcloud container images list-tags mirror.gcr.io/library/python
```

## create artifact repo

```bash
gcloud services enable \
  artifactregistry.googleapis.com

export REGION=us-east4
export REPO_NAME=tools
gcloud -q artifacts repositories create ${REPO_NAME} \
  --repository-format docker --location ${REGION}
```

## build the container using cloud build
```bash
gcloud builds submit . --config=cloudbuild-proxy.yaml

# confirm the container is built
export PROJECT_ID=$(gcloud config list --format "value(core.project)")
export PROXY_IMAGE=k8s-api-proxy
export PROXY_IMAGE_URL=${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE}
gcloud artifacts docker images list ${PROXY_IMAGE_URL}
```

## Build an image for cloud run
Some instructions are covered [here](https://cloud.google.com/run/docs/quickstarts/build-and-deploy/python):

```bash
gcloud builds submit . --config=cloudbuild-cloudrun.yaml
```

## Deploy a vpc connector for cloud run
More info [here](https://cloud.google.com/vpc/docs/configure-serverless-vpc-access). First let's create a dedicated subnet for the vpc connector:

```bash
export REGION="us-central1"
export SUBNET="vpc-connectors"
export HOST_PROJECT_ID="blah-blah"
export VPC_NAME="spoke"
export SUBNET_CIDR="10.12.0.0/28"
gcloud compute networks subnets create ${SUBNET} \
  --network ${VPC_NAME} --range ${SUBNET_CIDR} \
  --region ${REGION}
```

Now let's create the connector:

```bash
gcloud services enable vpcaccess.googleapis.com
export VPC_CONNECTOR_NAME="cloud-run-connector"

gcloud compute networks vpc-access connectors create ${VPC_CONNECTOR_NAME} \
--region ${REGION} \
--subnet ${SUBNET} \
--subnet-project HOST_PROJECT_ID \
```

## Deploy a container to cloud run
This should take care of it:

```bash
gcloud services enable run.googleapis.com
export REPO_REGION="us-east4"
export REPO_NAME="tools"
export GKE_NAME="private-cluster"
export GKE_REGION="us-central1"
export GKE_ZONE="${GKE_REGION}-c"
export PROJECT_ID=$(gcloud config list --format "value(core.project)")
export CLOUDRUN_IMAGE=cloudrun-deploy-to-k8s
export CLOUDRUN_IMAGE_URL=${REPO_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${CLOUDRUN_IMAGE}
export PROXY_IMAGE=k8s-api-proxy
export PROXY_IMAGE_URL=${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${PROXY_IMAGE}
export CLOUD_RUN_SVC_NAME="deploy-proxy"

gcloud run deploy ${CLOUD_RUN_SVC_NAME} --image ${CLOUDRUN_IMAGE_URL} \
  --port 8000 --set-env-vars "PROJECT_ID=${PROJECT_ID}","ZONE=${GKE_ZONE}","GKE_CLUSTER_NAME=${GKE_NAME}","K8S_API_PROXY_IMAGE=${PROXY_IMAGE_URL}" \
  --vpc-connector ${VPC_CONNECTOR_NAME} \
  --vpc-egress all-traffic \
  --platform managed \
  --region ${GKE_REGION} \
  --ingress all
```
