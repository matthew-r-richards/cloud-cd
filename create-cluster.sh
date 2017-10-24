#!/bin/bash
set -e

source scripts/utils.sh
source scripts/config.sh
source scripts/build-docker-images.sh

# Formatting constants
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

isJenkinsCluster() {
    [[ $TYPE = "jenkins" ]]
}

writeConfig() {
    CONFIG_FILE=.lastconfig
    rm $CONFIG_FILE
    echo "PROJECT_ID=$PROJECT_ID" >> $CONFIG_FILE
    echo "KEY_FILE=$KEY_FILE" >> $CONFIG_FILE
    echo "NETWORK_NAME=$NETWORK_NAME" >> $CONFIG_FILE
    echo "CLUSTER_NAME=$CLUSTER_NAME" >> $CONFIG_FILE
    echo "PDISK_NAME=$PDISK_NAME" >> $CONFIG_FILE
    echo "K8S_NAMESPACE=$K8S_NAMESPACE" >> $CONFIG_FILE
    echo "INGRESS_NAME=$INGRESS_NAME" >> $CONFIG_FILE
}

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

    # Set default zone
    echo "$BOLD---- Setting default Compute Zone to '$CLUSTER_ZONE'$NORMAL"
    gcloud config set compute/zone $CLUSTER_ZONE

    # Build the Jenkins images and push to the container repo
    MASTER_IMAGE_TAG="gcr.io/$PROJECT_ID/$MASTER_IMAGE"
    SLAVE_IMAGE_TAG="gcr.io/$PROJECT_ID/$SLAVE_IMAGE"

    if isJenkinsCluster; then
        buildJenkinsImages $MASTER_IMAGE_TAG $SLAVE_IMAGE_TAG
    else
        buildTeamcityImages $MASTER_IMAGE_TAG $SLAVE_IMAGE_TAG
    fi

    # Create a dedicated network
    if networkExists $NETWORK_NAME; then
        echo "$BOLD---- Network '$NETWORK_NAME' already exists$NORMAL"
    else
        echo "$BOLD---- Creating '$NETWORK_NAME' Network$NORMAL"
        gcloud compute networks create $NETWORK_NAME --mode auto 2> /dev/null
    fi

    # Create the kubernetes cluster
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

    # Create the persistent disk for the config
    if diskExists $PDISK_NAME; then
        echo "$BOLD---- Persistent Disk '$PDISK_NAME' already exists$NORMAL"
    else
        echo "$BOLD---- Creating Persistent Disk '$PDISK_NAME'$NORMAL"
        gcloud compute disks create $PDISK_NAME --size $PDISK_SIZE
    fi

    # Create a kubernetes namespace
    if k8sNamespaceExists $K8S_NAMESPACE; then
        echo "$BOLD---- Kubernetes Namespace '$K8S_NAMESPACE' already exists$NORMAL"
    else
        echo "$BOLD---- Creating Kubernetes Namespace '$K8S_NAMESPACE'$NORMAL"
        kubectl create namespace $K8S_NAMESPACE
    fi

    # Create the kubernetes services
    echo "$BOLD---- Creating Services in cluster$NORMAL"
    if isJenkinsCluster; then
        kubectl apply -f ./jenkins/k8s/service_jenkins.yaml
    else
        kubectl apply -f ./teamcity/k8s/service_teamcity.yaml
    fi


    # Create the kubernetes deployment
    echo "$BOLD---- Creating Deployment in cluster$NORMAL"
    if isJenkinsCluster; then
        kubectl apply -f ./jenkins/k8s/deployment_jenkins.yaml
    else
        kubectl apply -f ./teamcity/k8s/deployment_teamcity.yaml
    fi

    # Create temporary SSL certificate and create a corresponding kubernetes secret
    echo "$BOLD---- Creating temporary SSL certificate$NORMAL"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -subj "/CN=jenkins/O=jenkins"

    if k8sTlsSecretExists $K8S_NAMESPACE tls; then
    echo "$BOLD---- Deleting existing TLS secret in cluster$NORMAL"
        kubectl -n $K8S_NAMESPACE delete secret tls
    fi
    echo "$BOLD---- Creating Kubernetes TLS Secret$NORMAL"
    kubectl create secret generic tls --from-file=/tmp/tls.crt --from-file=/tmp/tls.key --namespace $K8S_NAMESPACE

    # Create the ingress resource
    echo "$BOLD---- Creating Ingress in cluster$NORMAL"
    if isJenkinsCluster; then
        kubectl apply -f ./jenkins/k8s/ingress_jenkins.yaml
    else
        kubectl apply -f ./teamcity/k8s/ingress_teamcity.yaml
    fi

    echo "$BOLD---- Waiting for external IP....$NORMAL"
    EXTERNAL_IP=""
    while [[ -z $EXTERNAL_IP ]]; do
        sleep 10
        EXTERNAL_IP=$(kubectl get -n $K8S_NAMESPACE ingress/$INGRESS_NAME --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
    done
    echo "The application can be reached at https://$EXTERNAL_IP"

    if isJenkinsCluster; then
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
        $(echo $INITIAL_PWD > ./jenkins/initialAdminPassword)
        echo "Initial Admin Password is $INITIAL_PWD and is also saved in ./jenkins/initialAdminPassword"
    fi

    echo "$BOLD---- Complete$NORMAL"
}

if [[ -z $1 ]] || [[ -z $2 ]]; then
    echo Usage create-cluster.sh [jenkins/teamcity] [path-to-key-file.json]
    exit
else
    TYPE=$1
    KEY_FILE=$2
fi

if [[ ! -f $KEY_FILE ]]; then
    echo "Key file $KEY_FILE not found"
    exit
fi

if [[ $TYPE = "jenkins" ]]; then
    MASTER_IMAGE=$JENKINS_MASTER_IMAGE
    SLAVE_IMAGE=$JENKINS_SLAVE_IMAGE
    NETWORK_NAME=$JENKINS_NETWORK_NAME
    CLUSTER_NAME=$JENKINS_CLUSTER_NAME
    PDISK_NAME=$JENKINS_PDISK_NAME
    K8S_NAMESPACE=$JENKINS_K8S_NAMESPACE
    INGRESS_NAME=$JENKINS_INGRESS_NAME
elif [[ $TYPE = "teamcity" ]]; then
    MASTER_IMAGE=$TEAMCITY_SERVER_IMAGE
    SLAVE_IMAGE=$TEAMCITY_AGENT_IMAGE
    NETWORK_NAME=$TEAMCITY_NETWORK_NAME
    CLUSTER_NAME=$TEAMCITY_CLUSTER_NAME
    PDISK_NAME=$TEAMCITY_PDISK_NAME
    K8S_NAMESPACE=$TEAMCITY_K8S_NAMESPACE
    INGRESS_NAME=$TEAMCITY_INGRESS_NAME
else
    echo "Unknown deployment type: $TYPE"
    exit
fi

writeConfig
create