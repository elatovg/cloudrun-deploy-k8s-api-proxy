#!/usr/bin/env python3
"""
Simple Flask App to deploy a
deployment to a gke cluster
"""
from flask import Flask, json, Response
from google.cloud import container_v1
import googleapiclient.discovery
from tempfile import NamedTemporaryFile
import kubernetes
import base64
import os

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
        cert.write(base64.decodebytes(response.master_auth.cluster_ca_certificate.encode()))
        config.ssl_ca_cert = cert.name

    client = kubernetes.client.ApiClient(configuration=config)
    # api = kubernetes.client.CoreV1Api(client)

    return client

def update_image(f_name):
    """
    update deploy yaml file for k8s
    """
    #read input file
    orig = open(f_name, "rt")
    data = orig.read()
    if 'K8S_API_PROXY_IMAGE' in os.environ:
        new_image = os.environ.get('K8S_API_PROXY_IMAGE')
    else:
        new_image = 'default'
    data = data.replace('IMAGE', new_image)
    #close the input file
    orig.close()
    orig = open(f_name, "wt")
    #overwrite the input file
    orig.write(data)
    orig.close()

app = Flask(__name__)


@app.route('/status', methods=['GET'])
def get_status():
    """ Return HTTP Code 200 """
    data = {
        'status': 'up',
    }
    jsn = json.dumps(data)

    resp = Response(jsn, status=200, mimetype='application/json')

    return resp


@app.route('/')
def deploy_to_k8s():
    """ Return a simple string"""
    api = kubernetes_api()
    update_image("dep.yaml")
    yaml_files = ["dep.yaml", "svc.yaml"]

    for yfile in yaml_files:
        kubernetes.utils.create_from_yaml(api,yfile)

    return "success"
if __name__ == "__main__":
    # app.run(debug=True)
    app.run(host="0.0.0.0", port=8000)
