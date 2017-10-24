#!/bin/bash

set -e

source scripts/utils.sh
source scripts/create-cluster.sh
source config.sh

create() {
    # Check that the binary dependencies are available
    commandExists gcloud
    commandExists kubectl
    commandExists openssl
    commandExists docker

    # Connect as the service account
    gcloudLogin $KEY_FILE

    # Set default project
    echo "$BOLD---- Setting default Project to '$PROJECT_ID'$NORMAL"
    gcloud config set core/project $PROJECT_ID

    # Check the required API(s) are enabled
    checkApis

    # Build the Jenkins master image and push to the container repo
    IMAGE_TAG="gcr.io/$PROJECT_ID/$MASTER_IMAGE"
    echo "$BOLD---- Build Jenkins Master Docker Image$NORMAL"
    docker build -t $IMAGE_TAG -f ./jenkins/docker/jenkins-master.dockerfile ./jenkins/docker
    echo "$BOLD---- Pushing to Google Container Repository$NORMAL"
    gcloud docker -- push $IMAGE_TAG
    echo "$BOLD---- Image name is $IMAGE_TAG$NORMAL"

    # Build the Jenkins slave image and push to the container repo
    IMAGE_TAG="gcr.io/$PROJECT_ID/$SLAVE_IMAGE"
    echo "$BOLD---- Build Jenkins Slave Docker Image$NORMAL"
    docker build -t $IMAGE_TAG -f ./jenkins/docker/jenkins-slave.dockerfile ./jenkins/docker
    echo "$BOLD---- Pushing to Google Container Repository$NORMAL"
    gcloud docker -- push $IMAGE_TAG
    echo "$BOLD---- Image name is $IMAGE_TAG$NORMAL"

    # Set default zone
    echo "$BOLD---- Setting default Compute Zone to '$CLUSTER_ZONE'$NORMAL"
    gcloud config set compute/zone $CLUSTER_ZONE

    # Create a dedicated network for Jenkins
    if networkExists $NETWORK_NAME; then
        echo "$BOLD---- Network '$NETWORK_NAME' already exists$NORMAL"
    else
        echo "$BOLD---- Creating '$NETWORK_NAME' Network$NORMAL"
        gcloud compute networks create $NETWORK_NAME --mode auto 2> /dev/null
    fi

    # Create the kubernetes cluster that jenkins will run on
    if clusterExists $CLUSTER_NAME; then
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
    if diskExists $PDISK_NAME; then
        echo "$BOLD---- Persistent Disk '$PDISK_NAME' already exists$NORMAL"
    else
        echo "$BOLD---- Creating Persistent Disk '$PDISK_NAME'$NORMAL"
        gcloud compute disks create $PDISK_NAME --size $PDISK_SIZE
    fi

    # Create the jenkins kubernetes namespace
    if k8sNamespaceExist $K8S_NAMESPACEs; then
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

    if k8sTlsSecretExists $K8S_NAMESPACE $TLS_SECRET_NAME; then
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
    echo "---- Initial Admin Password is $INITIAL_PWD and is also saved in ./jenkins/initialAdminPassword"

    echo "$BOLD---- Complete$NORMAL"
}

if [[ -z $1 ]]; then
    echo Usage create-jenkins-cluster.sh [path-to-key-file.json]
    exit
else
    KEY_FILE=$1
fi

if [[ ! -f $KEY_FILE ]]; then
    echo "Key file $KEY_FILE not found"
    exit
fi

create