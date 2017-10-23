#!/bin/bash

set -e

PROJECT_ID=jenkins-continuous-deployment
MASTER_IMAGE_NAME=jenkins-master
SLAVE_IMAGE_NAME=jenkins-slave
JENKINS_MASTER_VER=2.85
JENKINS_SLAVE_VER=3.7-1
NETWORK_NAME=jenkins
CLUSTER_NAME=jenkins-cd
CLUSTER_ZONE=europe-west3-a
CLUSTER_NODE_COUNT=1
CLUSTER_NODE_TYPE=n1-standard-2
PDISK_NAME=jenkins-home
PDISK_SIZE=10GB
K8S_NAMESPACE=jenkins
TLS_SECRET_NAME=tls
INGRESS_NAME=jenkins-ingress
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

commandExists() {
  if [[ ! `command -v $1` ]]; then
    echo "'$1' Application not found"
    exit
  fi
}

login() {
    echo "$BOLD---- Connecting as service account using the key file $KEY_FILE$NORMAL"
    gcloud auth activate-service-account --key-file=$KEY_FILE
}

apiEnabled() {
    [[ ! -z $(gcloud service-management list --enabled 2> /dev/null | grep $1) ]]
}

checkApis() {
    echo "$BOLD---- Checking Google APIs for Project$NORMAL"
    if apiEnabled compute.googleapis.com; then
        echo "---- Compute API already enabled"
    else
        echo "---- Enabling Compute API"
        gcloud service-management enable compute.googleapis.com
    fi

    if apiEnabled container.googleapis.com; then
        echo "---- Container Engine API already enabled"
    else
        echo "---- Enabling Container Engine API"
        gcloud service-management enable container.googleapis.com
    fi

    if apiEnabled containerregistry.googleapis.com; then
        echo "---- Container Registry API already enabled"
    else
        echo "---- Enabling Container Registry API"
        gcloud service-management enable containerregistry.googleapis.com
    fi
}

networkExists() {
    [[ ! -z $(gcloud compute networks list 2> /dev/null | grep $NETWORK_NAME) ]]
}

clusterExists() {
    [[ ! -z $(gcloud container clusters list 2> /dev/null | grep $CLUSTER_NAME) ]]
}

diskExists() {
    [[ ! -z $(gcloud compute disks list 2> /dev/null | grep $PDISK_NAME) ]]
}

diskImageExists() {
    [[ ! -z $(gcloud compute images list 2> /dev/null | grep $PDISK_NAME-image) ]]
}

k8sNamespaceExists() {
    [[ ! -z $(kubectl get namespaces 2>&1 | grep "$K8S_NAMESPACE") ]]
}

k8sTlsSecretExists() {
    [[ ! -z $(kubectl get secrets -n $K8S_NAMESPACE 2>&1 | grep tls) ]]
}

k8sServicesExist() {
    [[ ! -z $(kubectl get services -n $K8S_NAMESPACE 2>&1 | grep jenkins) ]]
}

k8sDeploymentExists() {
    [[ ! -z $(kubectl get deployments -n $K8S_NAMESPACE 2>&1 | grep jenkins) ]]
}

k8sIngressExists() {
    [[ ! -z $(kubectl get ingress -n $K8S_NAMESPACE 2>&1 | grep jenkins) ]]
}

create() {
    # Check that the binary dependencies are available
    commandExists gcloud
    commandExists kubectl
    commandExists openssl
    commandExists docker

    # Connect as the service account
    login

    # Set default project
    echo "$BOLD---- Setting default Project to '$PROJECT_ID'$NORMAL"
    gcloud config set core/project $PROJECT_ID

    # Check the required API(s) are enabled
    checkApis

    # Build the Jenkins master image and push to the container repo
    IMAGE_TAG="gcr.io/$PROJECT_ID/$MASTER_IMAGE_NAME:$JENKINS_MASTER_VER"
    echo "$BOLD---- Build Jenkins Master Docker Image$NORMAL"
    docker build -t $IMAGE_TAG -f ./jenkins/docker/jenkins-master.dockerfile ./jenkins/docker
    echo "$BOLD---- Pushing to Google Container Repository$NORMAL"
    gcloud docker -- push $IMAGE_TAG
    echo "$BOLD---- Image name is $IMAGE_TAG$NORMAL"

    # Build the Jenkins slave image and push to the container repo
    IMAGE_TAG="gcr.io/$PROJECT_ID/$SLAVE_IMAGE_NAME:$JENKINS_SLAVE_VER"
    echo "$BOLD---- Build Jenkins Slave Docker Image$NORMAL"
    docker build -t $IMAGE_TAG -f ./jenkins/docker/jenkins-slave.dockerfile ./jenkins/docker
    echo "$BOLD---- Pushing to Google Container Repository$NORMAL"
    gcloud docker -- push $IMAGE_TAG
    echo "$BOLD---- Image name is $IMAGE_TAG$NORMAL"

    # Set default zone
    echo "$BOLD---- Setting default Compute Zone to '$CLUSTER_ZONE'$NORMAL"
    gcloud config set compute/zone $CLUSTER_ZONE

    # Create a dedicated network for Jenkins
    if networkExists; then
        echo "$BOLD---- Network '$NETWORK_NAME' already exists$NORMAL"
    else
        echo "$BOLD---- Creating '$NETWORK_NAME' Network$NORMAL"
        gcloud compute networks create $NETWORK_NAME --mode auto 2> /dev/null
    fi

    # Create the kubernetes cluster that jenkins will run on
    if clusterExists; then
        echo "$BOLD---- Cluster '$CLUSTER_NAME' already exists$NORMAL"
    else
        echo "$BOLD---- Creating '$CLUSTER_NAME' Cluster$NORMAL"
        gcloud container clusters create $CLUSTER_NAME \
            --network $NETWORK_NAME \
            --scopes storage-rw \
            --num-nodes $CLUSTER_NODE_COUNT \
            --machine-type $CLUSTER_NODE_TYPE
    fi

    # Create the persistent disk for the Jenkins config
    if diskExists; then
        echo "$BOLD---- Persistent Disk '$PDISK_NAME' already exists$NORMAL"
    else
        echo "$BOLD---- Creating Persistent Disk '$PDISK_NAME'$NORMAL"
        gcloud compute disks create $PDISK_NAME --size $PDISK_SIZE
    fi

    # Create the jenkins kubernetes namespace
    if k8sNamespaceExists; then
        echo "$BOLD---- Kubernetes Namespace '$K8S_NAMESPACE' already exists$NORMAL"
    else
        echo "$BOLD---- Creating Kubernetes Namespace '$K8S_NAMESPACE'$NORMAL"
        kubectl create namespace $K8S_NAMESPACE
    fi

    # Create the kubernetes services
    echo "$BOLD---- Creating Jenkins Services in cluster$NORMAL"
    kubectl apply -f ./jenkins/k8s/service_jenkins.yaml

    # Create the kubernetes deployment
    echo "$BOLD---- Creating Jenkins Deployment in cluster$NORMAL"
    kubectl apply -f ./jenkins/k8s/jenkins.yaml

    # Create temporary SSL certificate and create a corresponding kubernetes secret
    echo "$BOLD---- Creating temporary SSL certificate$NORMAL"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -subj "/CN=jenkins/O=jenkins"

    if k8sTlsSecretExists; then
    echo "$BOLD---- Deleting existing Jenkins TLS secret in cluster$NORMAL"
        kubectl -n $K8S_NAMESPACE delete secret $TLS_SECRET_NAME
    fi
    echo "$BOLD---- Creating Kubernetes TLS Secret$NORMAL"
    kubectl create secret generic $TLS_SECRET_NAME --from-file=/tmp/tls.crt --from-file=/tmp/tls.key --namespace $K8S_NAMESPACE

    # Create the ingress resource
    echo "$BOLD---- Creating Jenkins Ingress in cluster$NORMAL"
    kubectl apply -f ./jenkins/k8s/ingress_jenkins.yaml

    echo "$BOLD---- Waiting for external IP....$NORMAL"
    EXTERNAL_IP=""
    while [[ -z $EXTERNAL_IP ]]; do
        sleep 10
        EXTERNAL_IP=$(kubectl get -n $K8S_NAMESPACE ingress/$INGRESS_NAME --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
    done
    echo "---- Jenkins can be reached at https://$EXTERNAL_IP"

    # Get the initial admin password from the pod
    echo "$BOLD---- Waiting for Jenkins to start up....$NORMAL"
    POD_NAME=$(kubectl get pod -n $K8S_NAMESPACE --selector=app=master -o jsonpath="{.items[0].metadata.name}")

    if [[ -z $POD_NAME ]]; then
        echo "Jenkins master pod not found in $K8S_NAMESPACE namespace"
        exit
    fi

    INITIAL_PWD=""
    while [[ -z $INITIAL_PWD ]]; do
        sleep 5
        INITIAL_PWD=$(kubectl exec -n $K8S_NAMESPACE $POD_NAME cat /var/jenkins_home/secrets/initialAdminPassword 2> /dev/null)
    done
    $(echo $INITIAL_PWD > ./initialAdminPassword)
    echo "---- Initial Admin Password is $INITIAL_PWD and is also saved in ./initialAdminPassword"

    echo "$BOLD---- Complete$NORMAL"
}

delete() {
    # Check that the gcloud SDK is available
    commandExists gcloud

    login

    # Check the required API(s) are enabled
    checkApis

    if k8sNamespaceExists; then
        echo "$BOLD---- Deleting $K8S_NAMESPACE namespace$NORMAL"
        kubectl delete ns $K8S_NAMESPACE
    fi

    if clusterExists; then
        echo "$BOLD---- Deleting $CLUSTER_NAME cluster$NORMAL"
        gcloud container clusters delete $CLUSTER_NAME --zone $CLUSTER_ZONE --quiet
    fi

    if diskExists; then
        echo "$BOLD---- Deleting $PDISK_NAME persistent disk$NORMAL"
        gcloud compute disks delete $PDISK_NAME --zone $CLUSTER_ZONE --quiet
    fi

    echo "$BOLD---- Deleting firewall rules$NORMAL"
    for rule in $(gcloud compute firewall-rules list --filter network~jenkins --format='value(name)'  2> /dev/null); do
        echo "Deleting $rule..."
        gcloud compute firewall-rules delete $rule --quiet
    done

    echo "$BOLD---- Deleting forwarding rules$NORMAL"
    for rule in $(gcloud compute forwarding-rules list --filter="name~.*$K8S_NAMESPACE-$INGRESS_NAME.*"  --format='value(name)' 2> /dev/null); do
        echo "Deleting $rule..."
        gcloud compute forwarding-rules delete $rule --global --quiet
    done

    echo "$BOLD---- Deleting addresses$NORMAL"
    for address in $(gcloud compute addresses list --filter="name~.*$K8S_NAMESPACE-$INGRESS_NAME.*"  --format='value(name)' 2> /dev/null); do
     gcloud compute addresses delete $address --global --quiet
    done

    echo "$BOLD---- Deleting HTTPS proxies$NORMAL"
    for proxy in $(gcloud compute target-https-proxies list --filter="name~.*$K8S_NAMESPACE-$INGRESS_NAME.*"  --format='value(name)' 2> /dev/null); do
        echo "Deleting $proxy..."
        gcloud compute target-https-proxies delete $proxy --quiet
    done

    echo "$BOLD---- Deleting SSL certificates$NORMAL"
    for cert in $(gcloud compute ssl-certificates list --filter="name~.*$K8S_NAMESPACE-$INGRESS_NAME.*"  --format='value(name)' 2> /dev/null); do
        echo "Deleting $cert..."
        gcloud compute ssl-certificates delete $cert --quiet
    done

    echo "$BOLD---- Deleting target pools$NORMAL"
    for target in $(gcloud compute target-pools list --filter="name~.*$K8S_NAMESPACE-$INGRESS_NAME.*"  --format='value(name)' 2> /dev/null); do
        echo "Deleting $target"
        gcloud compute target-pools delete $target --quiet
    done

    echo "$BOLD---- Deleting URL maps$NORMAL"
    for url in $(gcloud compute url-maps list --filter="name~.*$K8S_NAMESPACE-$INGRESS_NAME.*"  --format='value(name)' 2> /dev/null); do
        echo "Deleting $url"
        gcloud compute url-maps delete $url --quiet
    done

    if networkExists; then
        echo "$BOLD---- Deleting $NETWORK_NAME network$NORMAL"
        gcloud compute networks delete $NETWORK_NAME --quiet
    fi

    echo "$BOLD---- Complete$NORMAL"
}

if [[ -z $1 ]] | [[ -z $2 ]]; then
    echo Usage jenkins-cluster.sh [create/delete] [path-to-key-file.json]
    exit
else
    COMMAND=$1
    KEY_FILE=$2
fi

if [[ ! -f $KEY_FILE ]]; then
    echo "Key file $2 not found"
    exit
fi

if [[ $COMMAND = "create" ]]; then
    create
    exit
fi

if [[ $COMMAND = "delete" ]]; then
    delete
    exit
fi