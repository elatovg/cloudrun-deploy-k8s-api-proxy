# cloud{run,fn}-deploy-k8s-api-proxy

## Base Config
### confirm your base images exist
GCR [Mirrors dockerhub](https://cloud.google.com/container-registry/docs/pulling-cached-images)

```bash
> gcloud container images list --repository=mirror.gcr.io/library | grep alpine
mirror.gcr.io/library/alpine
```

Also list the tags to see which one you want to build from (for example):

```bash
gcloud container images list-tags mirror.gcr.io/library/python
```

### create artifact repo

```bash
gcloud services enable \
  artifactregistry.googleapis.com

export REPO_REGION=us-east4
export REPO_NAME=tools
gcloud -q artifacts repositories create ${REPO_NAME} \
  --repository-format docker --location ${REGION}
```

### build the container using cloud build
```bash
gcloud services enable cloudbuild.googleapis.com
gcloud builds submit . --config=cloudbuild-proxy.yaml

# confirm the container is built
export PROJECT_ID=$(gcloud config list --format "value(core.project)")
export PROXY_IMAGE=k8s-api-proxy
export PROXY_IMAGE_URL=${REPO_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE}
gcloud artifacts docker images list ${PROXY_IMAGE_URL}
```

### Deploy a VPC connector for serverless
More info [here](https://cloud.google.com/vpc/docs/configure-serverless-vpc-access). First let's create a dedicated subnet for the vpc connector:

```bash
export REGION="us-central1"
export SUBNET="vpc-connectors"
export HOST_PROJECT_ID="blah-blah"
export VPC_NAME="spoke"
export SUBNET_CIDR="10.12.0.0/28"
gcloud compute networks subnets create ${SUBNET} \
  --network ${VPC_NAME} --range ${SUBNET_CIDR} \
  --enable-private-ip-google-access \
  --region ${REGION}
```

Now let's create the connector:

```bash
gcloud services enable vpcaccess.googleapis.com
export VPC_CONNECTOR_NAME="cloud-run-connector"

gcloud compute networks vpc-access connectors create ${VPC_CONNECTOR_NAME} \
  --region ${REGION} --subnet ${SUBNET} --subnet-project HOST_PROJECT_ID 
```

Add the subnet to the authorized networks for the GKE cluster:

```bash
export GKE_NAME="private-cluster"
gcloud container clusters update ${GKE_NAME} \
    --enable-master-authorized-networks \
    --master-authorized-networks ${SUBNET_CIDR}
```

### Enable private google access for googleapis.com
First create the dns zone:

```bash
export DOMAIN="googleapis.com"
export UDOMAIN="${DOMAIN//./-}"
export VPC_NAME="spoke"

# create the zone
gcloud dns managed-zones \
  create ${UDOMAIN} --description "" \
  --dns-name "${DOMAIN}." --visibility "private" \
  --networks "${VPC_NAME}"


gcloud dns record-sets transaction start --zone ${UDOMAIN}

# create the A record
gcloud dns record-sets transaction add 199.36.153.8 199.36.153.9 199.36.153.10 199.36.153.11 \
  --name "private.${DOMAIN}." --ttl 300 --type A --zone "${UDOMAIN}"

# create the CNAME record
gcloud dns record-sets transaction add \
  "private.${DOMAIN}." --name \*.${DOMAIN}. --ttl 300 --type CNAME --zone ${UDOMAIN}

gcloud dns record-sets transaction execute --zone "${UDOMAIN}"
```

Now let's create the dns zone for artifact registry:


```bash
export DOMAIN="pkg.dev"
export UDOMAIN="${DOMAIN//./-}"
export VPC_NAME="spoke"

# create the zone
gcloud dns managed-zones \
  create ${UDOMAIN} --description "" \
  --dns-name "${DOMAIN}." --visibility "private" --networks "${VPC_NAME}"


gcloud dns record-sets transaction start --zone ${UDOMAIN}

# create the A record
gcloud dns record-sets transaction add 199.36.153.8 199.36.153.9 199.36.153.10 199.36.153.11 \
  --name "${DOMAIN}." --ttl 300 --type A --zone "${UDOMAIN}"

# create the CNAME record
gcloud dns record-sets transaction add "${DOMAIN}." --name \*.${DOMAIN}. \
  --ttl 300 --type CNAME --zone ${UDOMAIN}

gcloud dns record-sets transaction execute --zone "${UDOMAIN}"
```

If you don't a route to the default-internet-gateway for the DNS servers, add them:

```bash
export VPC_NAME="spoke"
gcloud compute routes create access-googleapis \
  --network ${VPC_NAME} --destination-range 199.36.153.8/30 \
  --next-hop-gateway default-internet-gateway --priority 90
```

### Create a pubsub topic
```bash
export PUBSUB_TOPIC="k8s-api-proxy"
gcloud pubsub topics create ${PUBSUB_TOPIC}
```

## Cloud Run Approach
### Build an image for cloud run
Some instructions are covered [here](https://cloud.google.com/run/docs/quickstarts/build-and-deploy/python):

```bash
gcloud builds submit . --config=cloudbuild-cloudrun.yaml
```

### Deploy a container to cloud run
This should take care of it:

```bash
gcloud services enable run.googleapis.com
export REPO_REGION="us-east4"
export REPO_NAME="tools"
export GKE_NAME="private-cluster"
export GKE_REGION="us-central1"
export GKE_ZONE="${GKE_REGION}-c"
export PROJECT_ID=$(gcloud config list --format "value(core.project)")
export CLOUDRUN_IMAGE="cloudrun-deploy-to-k8s"
export CLOUDRUN_IMAGE_URL=${REPO_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${CLOUDRUN_IMAGE}
export PROXY_IMAGE="k8s-api-proxy"
export PROXY_IMAGE_URL=${REPO_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${PROXY_IMAGE}
export CLOUD_RUN_SVC_NAME="deploy-proxy"
export VPC_CONNECTOR_NAME="cloud-run-connector"

gcloud run deploy ${CLOUD_RUN_SVC_NAME} --image ${CLOUDRUN_IMAGE_URL} \
  --port 8000 --set-env-vars "PROJECT_ID=${PROJECT_ID}","ZONE=${GKE_ZONE}","GKE_CLUSTER_NAME=${GKE_NAME}","K8S_API_PROXY_IMAGE=${PROXY_IMAGE_URL}" \
  --vpc-connector ${VPC_CONNECTOR_NAME} --vpc-egress all-traffic \
  --platform managed --region ${GKE_REGION} --ingress all
```

That will show you the link for the cloudrun instance, then you can run the following to kick it off:

```bash
curl https://deploy-proxy-s7g6cfdg5q-uc.a.run.app
success%
```

Wait a couple of minutes and get the IP of the ILB:

```bash
curl https://deploy-proxy-s7g6cfdg5q-uc.a.run.app/get_svc_ip
10.150.0.13%
```

If you want you can also delete the deployment:

```bash
curl https://deploy-proxy-s7g6cfdg5q-uc.a.run.app/del
success%
```

## Cloud Function Approach

### Mirror Github Repo to Cloud Source Repositories
All the instructions are laid out in [Mirroring a GitHub repository](https://cloud.google.com/source-repositories/docs/mirroring-a-github-repository)

### Create the cloud function

```bash
export PROJECT_ID=$(gcloud config list --format 'value(core.project)')
export REGION="us-central1"
export GKE_ZONE="us-central1-c"
export GKE_CLUSTER_NAME="private-cluster"
export REPO_REGION="us-east4"
export REPO_NAME="tools"
export PROXY_IMAGE_URL="${REPO_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${PROXY_IMAGE}"
export PUBSUB_TOPIC="k8s-api-proxy"
export CLOUD_SOURCE_REPO="github_elatovg_cloudrun-deploy-k8s-api-proxy"
export SRC_PATH="https://source.developers.google.com/projects/${PROJECT_ID}/repos/${CLOUD_SOURCE_REPO}/moveable-aliases/main/paths/src/cloudfn/app"
export CLOUD_FN_NAME="deploy-proxy"
export VPC_CONNECTOR_NAME="cloud-run-connector"

gcloud functions deploy ${CLOUD_FN_NAME} --runtime python39 \
  --set-env-vars "PROJECT_ID=${PROJECT_ID},ZONE=${GKE_ZONE},GKE_CLUSTER_NAME=${GKE_CLUSTER_NAME},K8S_API_PROXY_IMAGE=${PROXY_IMAGE_URL}" \
  --trigger-topic ${PUBSUB_TOPIC} --entry-point main --region ${REGION} \ 
  --source ${SRC_PATH} --vpc-connector ${VPC_CONNECTOR_NAME} --egress-settings all \
  --ingress-settings all
```

To trigger the function, publish a message to the pubsub topic:

```bash
export PUBSUB_TOPIC="k8s-api-proxy"
gcloud pubsub topics publish ${PUBSUB_TOPIC} \
  --message "create"
```

To delete the deployment you can send the following pubsub message:

```bash
export PUBSUB_TOPIC="k8s-api-proxy"
gcloud pubsub topics publish ${PUBSUB_TOPIC} \
  --message "delete"
```

And to get the IP, you can run the following:

```bash
export PUBSUB_TOPIC="k8s-api-proxy"
gcloud pubsub topics publish ${PUBSUB_TOPIC} \
  --message "get-svc-ip"
```

You can then check out the logs:

```bash
> gcloud functions logs read deploy-proxy --region ${REGION}
LEVEL  NAME          EXECUTION_ID  TIME_UTC                 LOG
D      deploy-proxy  mfvgl08ld897  2021-08-14 18:38:07.989  Function execution took 234 ms, finished with status: 'ok'
       deploy-proxy  mfvgl08ld897  2021-08-14 18:38:07.988  ILB IP is 100.126.190.42
       deploy-proxy  mfvgl08ld897  2021-08-14 18:38:07.760  Attempting to init k8s client from cluster response.
       deploy-proxy  mfvgl08ld897  2021-08-14 18:38:07.760  This Function was triggered by messageId 2812274547199873 published at 2021-08-14T18:38:06.680Z to projects/PROJECT_ID/topics/k8s-api-proxy
D      deploy-proxy  mfvgl08ld897  2021-08-14 18:38:07.756  Function execution started
D      deploy-proxy  mfvg6zgdj9gq  2021-08-14 18:36:47.055  Function execution took 2406 ms, finished with status: 'ok'
       deploy-proxy  mfvg6zgdj9gq  2021-08-14 18:36:47.051  Creation Finished
       deploy-proxy  mfvg6zgdj9gq  2021-08-14 18:36:47.049  [INFO] service `k8s-api-proxy` created
       deploy-proxy  mfvg6zgdj9gq  2021-08-14 18:36:46.842  [INFO] deployment k8s-api-proxy created
       deploy-proxy  mfvg6zgdj9gq  2021-08-14 18:36:46.585  Attempting to init k8s client from cluster response.
       deploy-proxy  mfvg6zgdj9gq  2021-08-14 18:36:46.584  This Function was triggered by messageId 2812274399922080 published at 2021-08-14T18:36:43.706Z to projects/PROJECT_ID/topics/k8s-api-proxy
D      deploy-proxy  mfvg6zgdj9gq  2021-08-14 18:36:44.650  Function execution started
```