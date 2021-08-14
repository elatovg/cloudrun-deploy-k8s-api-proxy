#!/usr/bin/env python3
"""
Simple Flask App to deploy a
deployment to a gke cluster
"""
from tempfile import NamedTemporaryFile
import base64
import os
from google.cloud import container_v1
import googleapiclient.discovery
import kubernetes


def token(*scopes):
    """
    Get Oauth Token for google apis
    """
    credentials = googleapiclient._auth.default_credentials()
    scopes = [f'https://www.googleapis.com/auth/{s}' for s in scopes]
    scoped = googleapiclient._auth.with_scopes(credentials, scopes)
    googleapiclient._auth.refresh_credentials(scoped)
    return scoped.token


def kubernetes_api():
    """
    Connect to GKE
    """
    if 'PROJECT_ID' in os.environ:
        project_id = os.environ.get('PROJECT_ID')
    else:
        project_id = 'default'

    if 'ZONE' in os.environ:
        zone = os.environ.get('ZONE')
    else:
        zone = 'us-central1-c'

    if 'GKE_CLUSTER_NAME' in os.environ:
        cluster_name = os.environ.get('GKE_CLUSTER_NAME')
    else:
        cluster_name = 'my-gke-cluster'
    print('Attempting to init k8s client from cluster response.')
    container_client = container_v1.ClusterManagerClient()
    # print(project_id)
    full_name = f"projects/{project_id}/locations/{zone}/clusters/{cluster_name}"
    response = container_client.get_cluster(name=full_name)
    # print(response)
    config = kubernetes.client.Configuration()
    config.host = f'https://{response.endpoint}'

    config.api_key_prefix['authorization'] = 'Bearer'
    config.api_key['authorization'] = token('cloud-platform')

    with NamedTemporaryFile(delete=False) as cert:
        cert.write(
            base64.decodebytes(
                response.master_auth.cluster_ca_certificate.encode()))
        config.ssl_ca_cert = cert.name

    # client = kubernetes.client.ApiClient(configuration=config)
    # api = kubernetes.client.CoreV1Api(client)
    client = kubernetes.dynamic.DynamicClient(
        kubernetes.client.ApiClient(configuration=config))

    return client


def update_image(manifest):
    """
    update deployment manifest with image value
    """
    if 'K8S_API_PROXY_IMAGE' in os.environ:
        new_image = os.environ.get('K8S_API_PROXY_IMAGE')
    else:
        new_image = 'default'

    manifest["spec"]["template"]["spec"]["containers"][0]["image"] = new_image
    return manifest


def deploy_to_k8s():
    """ Return a success string"""
    api = kubernetes_api()
    name = "k8s-api-proxy"

    dep_api = api.resources.get(api_version="apps/v1", kind="Deployment")

    deployment_manifest = {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "labels": {
                "app": name
            },
            "name": name
        },
        "spec": {
            "selector": {
                "matchLabels": {
                    "app": name
                }
            },
            "template": {
                "metadata": {
                    "labels": {
                        "app": name
                    }
                },
                "spec": {
                    "containers": [{
                        "name": name,
                        "image": "IMAGE",
                        "ports": [{
                            "containerPort": 8000
                        }],
                    }]
                },
            },
        },
    }

    # Creating deployment in the `default` namespace
    updated_deployment = update_image(deployment_manifest)

    _deployment = dep_api.create(body=updated_deployment, namespace="default")

    print(f"\n[INFO] deployment {name} created\n")

    svc_api = api.resources.get(api_version="v1", kind="Service")

    service_manifest = {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": {
            "labels": {
                "app": name
            },
            "name": name,
            "annotations": {
                "cloud.google.com/load-balancer-type": "Internal"
            }
        },
        "spec": {
            "ports": [{
                "name": "port",
                "port": 8118,
                "protocol": "TCP",
                "targetPort": 8118
            }],
            "selector": {
                "app": name
            },
            "type": "LoadBalancer"
        },
    }

    _service = svc_api.create(body=service_manifest, namespace="default")

    print(f"\n[INFO] service `{name}` created\n")

    return "success"


def del_from_k8s():
    """ Return a simple string"""
    api = kubernetes_api()
    name = "k8s-api-proxy"

    dep_api = api.resources.get(api_version="apps/v1", kind="Deployment")
    _deployment_deleted = dep_api.delete(name=name,
                                         body={},
                                         namespace="default")
    print(f"\n[INFO] deployment `{name}` deleted.")
    svc_api = api.resources.get(api_version="v1", kind="Service")
    _service_deleted = svc_api.delete(name=name, body={}, namespace="default")
    print(f"\n[INFO] service `{name}` deleted.")

    return "success"


def get_k8s_svc_ip():
    """ Return ip as a string"""
    api = kubernetes_api()
    name = "k8s-api-proxy"
    svc_api = api.resources.get(api_version="v1", kind="Service")
    service_info = svc_api.get(name=name, namespace="default")

    return service_info.status.loadBalancer.ingress[0].ip


def main(event, context):
    """ Main Entry point for the cloudfunction"""
    print(
        """This Function was triggered by messageId {} published at {} to {}""".
        format(context.event_id, context.timestamp, context.resource["name"]))

    if 'data' in event:
        action = base64.b64decode(event['data']).decode('utf-8')
    else:
        action = 'create'

    if action == "create":
        deploy_to_k8s()
        print("Creation Finished")
    elif action == "delete":
        del_from_k8s()
        print("Deletion Finished")
    elif action == "get-svc-ip":
        ip_addr = get_k8s_svc_ip()
        print(f"ILB IP is {ip_addr}")
