import os.path
import yaml
import boto3 
from kubernetes import client, config
import re
import base64
import string
import random
import datetime
import time
from botocore.signers import RequestSigner 

# Configure your cluster name and region here
global CLUSTER_NAME

KUBE_FILEPATH = '/tmp/kubeconfig'
AURORA_GDB_NAME = ''
REGION = os.environ['AWS_REGION']
K8S_NAMESPACE='retailapp'
K8S_CONFIGMAP='pgbconfig'
K8S_DEPLOYMENT='pgbouncer-deployment'


def get_bearer_token(cluster_id, region):
    STS_TOKEN_EXPIRES_IN = 60
    session = boto3.session.Session()

    client = session.client('sts', region_name=region)
    service_id = client.meta.service_model.service_id

    signer = RequestSigner(
        service_id,
        region,
        'sts',
        'v4',
        session.get_credentials(),
        session.events
    )

    params = {
        'method': 'GET',
        'url': 'https://sts.{}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15'.format(region),
        'body': {},
        'headers': {
            'x-k8s-aws-id': cluster_id
        },
        'context': {}
    }

    signed_url = signer.generate_presigned_url(
        params,
        region_name=region,
        expires_in=STS_TOKEN_EXPIRES_IN,
        operation_name=''
    )
    base64_url = base64.urlsafe_b64encode(signed_url.encode('utf-8')).decode('utf-8')
    return 'k8s-aws-v1.' + re.sub(r'=*', '', base64_url)


def create_kube_config():
    if not os.path.exists(KUBE_FILEPATH):
        eks_api = boto3.client('eks',region_name=REGION)
        cluster_info = eks_api.describe_cluster(name=CLUSTER_NAME)
        print(cluster_info)
        certificate = cluster_info['cluster']['certificateAuthority']['data']
        endpoint = cluster_info['cluster']['endpoint']
        cluster_arn = cluster_info['cluster']['arn']
        generating_kubeconfig(KUBE_FILEPATH,certificate,endpoint, cluster_arn)

def generating_kubeconfig(config_filepath,certificate,endpoint, cluster_arn):
    kube_content = dict()
    
    kube_content['apiVersion'] = 'v1'
    kube_content['clusters'] = [
        {
        'cluster':
            {
            'server': endpoint,
            'certificate-authority-data': certificate
            },
        'name': cluster_arn
                
        }]

    kube_content['contexts'] = [
        {
        'context':
            {
            'cluster':cluster_arn,
            'user':cluster_arn
            },
        'name':cluster_arn
        }]

    kube_content['current-context'] = cluster_arn
    kube_content['kind'] = 'Config'
    kube_content['users'] = [
        {
        'name':cluster_arn,
        'user':
            {
                'name':'lambda'
        }}]

    # Write kubeconfig
    with open(config_filepath, 'w') as outfile:
        yaml.dump(kube_content, outfile, default_flow_style=False)
        
def get_aurora_cluster_ep(region,once=True):
    rw_endpoint = None
    
    client = boto3.client('rds', region_name=region)
    db_cluster_info = client.describe_db_clusters()
    for db_cluster in db_cluster_info['DBClusters']:
        if len(db_cluster['TagList']) > 0:
            for tag in db_cluster['TagList']:
                if tag['Key'] == 'Application' and tag['Value'] == 'EKSAURGDB':
                    print(db_cluster.get('ReplicationSourceIdentifier'))
                    if db_cluster.get('ReplicationSourceIdentifier') is not None:
                        if once:
                            print("Current region {} is secondary".format(region))
                            remote_region = db_cluster['ReplicationSourceIdentifier'].split(":")[3]
                            print("Checking on the region {}".format(remote_region))
                            rw_endpoint = get_aurora_cluster_ep(remote_region, False)
                        else:
                            print("Already in the loop.. breaking it")
                            rw_endpoint = None
                    else:
                        rw_endpoint = db_cluster['Endpoint']

    return rw_endpoint
    
def patch_cm_data(cm_data, aurora_cluster_ep):
    #aurora_cluster_ep = "mytest1"
    new_cm_data = []
    
    for line in cm_data.split("\n"):
        if 'gdbdemo = host=' in line:
            print(line.split('=')[2])
            new_ep = line.replace(line.split('=')[2].split()[0],aurora_cluster_ep)
            new_cm_data.append(new_ep)
        else:
            new_cm_data.append(line)
    return '\n'.join(new_cm_data)
    
def restart_deployment(v1_apps):
    now = datetime.datetime.utcnow()
    now = str(now.isoformat("T") + "Z")
    body = {
        'spec': {
            'template':{
                'metadata': {
                    'annotations': {
                        'kubectl.kubernetes.io/restartedAt': now
                    }
                }
            }
        }
    }
    v1_apps.patch_namespaced_deployment(K8S_DEPLOYMENT, K8S_NAMESPACE, body, pretty='true')


def get_cluster_name():

    cluster_name = None
    client = boto3.client("cloudformation", region_name=REGION)
    response = client.describe_stacks()
    for stack in response['Stacks']:
        stackout = [] if not stack.get('Outputs') else stack.get('Outputs')
        for output in stackout:
            if output['OutputKey'] == 'EKSClusterName' :
                cluster_name = output['OutputValue']
                break
    return cluster_name

def lambda_handler(event, context):
    
    global CLUSTER_NAME

    CLUSTER_NAME=get_cluster_name()
    print("EKS clustername : {}".format(CLUSTER_NAME))
    aurora_cluster_ep = get_aurora_cluster_ep(REGION)
    print("Aurora cluster endpoint is {}".format(aurora_cluster_ep))
    
    create_kube_config()
    token = get_bearer_token(CLUSTER_NAME,REGION)
    config.load_kube_config(KUBE_FILEPATH)
    configuration = client.Configuration.get_default_copy()
    configuration.verify_ssl = False
    configuration.api_key['authorization'] = token
    configuration.api_key_prefix['authorization'] = 'Bearer'
    configuration.debug = False
   
    api = client.ApiClient(configuration) 
    v1 = client.CoreV1Api(api)
    v1_apps = client.AppsV1Api(api)
    cm = v1.read_namespaced_config_map(K8S_CONFIGMAP,K8S_NAMESPACE)
    cm_data = cm.data['pgbouncer.ini']
    new_cm_data = patch_cm_data(cm_data, aurora_cluster_ep)
    cm_patch = v1.patch_namespaced_config_map(K8S_CONFIGMAP,K8S_NAMESPACE, {"data" : {"pgbouncer.ini": new_cm_data}})

    restart_deployment(v1_apps)
    return({"status": "OK"})
