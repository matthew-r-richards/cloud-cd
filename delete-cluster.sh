#!/bin/bash

set -e

source scripts/utils.sh
source scripts/config.sh

# Formatting constants
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

delete() {
    # Check that the gcloud SDK is available
    commandExists gcloud

    gcloudLogin $KEY_FILE

    # Check the required API(s) are enabled
    checkApis

    if k8sNamespaceExists $K8S_NAMESPACE; then
        echo "$BOLD---- Deleting $K8S_NAMESPACE namespace$NORMAL"
        kubectl delete ns $K8S_NAMESPACE
    fi

    if clusterExists $CLUSTER_NAME; then
        echo "$BOLD---- Deleting $CLUSTER_NAME cluster$NORMAL"
        gcloud container clusters delete $CLUSTER_NAME --zone $CLUSTER_ZONE --quiet
    fi

    if diskExists $PDISK_NAME; then
        echo "$BOLD---- Deleting $PDISK_NAME persistent disk$NORMAL"
        gcloud compute disks delete $PDISK_NAME --zone $CLUSTER_ZONE --quiet
    fi

    echo "$BOLD---- Deleting firewall rules$NORMAL"
    for rule in $(gcloud compute firewall-rules list --filter network~$NETWORK_NAME --format='value(name)'  2> /dev/null); do
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

    if networkExists $NETWORK_NAME; then
        echo "$BOLD---- Deleting $NETWORK_NAME network$NORMAL"
        gcloud compute networks delete $NETWORK_NAME --quiet
    fi

    echo "$BOLD---- Complete$NORMAL"
}

if [[ -z $1 ]] || [[ -z $2 ]]; then
    echo Usage delete-cluster.sh [jenkins/teamcity] [path-to-key-file.json]
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
    NETWORK_NAME=$JENKINS_NETWORK_NAME
    CLUSTER_NAME=$JENKINS_CLUSTER_NAME
    PDISK_NAME=$JENKINS_PDISK_NAME
    K8S_NAMESPACE=$JENKINS_K8S_NAMESPACE
    INGRESS_NAME=$JENKINS_INGRESS_NAME
elif [[ $TYPE = "teamcity" ]]; then
    NETWORK_NAME=$TEAMCITY_NETWORK_NAME
    CLUSTER_NAME=$TEAMCITY_CLUSTER_NAME
    PDISK_NAME=$TEAMCITY_PDISK_NAME
    K8S_NAMESPACE=$TEAMCITY_K8S_NAMESPACE
    INGRESS_NAME=$TEAMCITY_INGRESS_NAME
else
    echo "Unknown deployment type: $TYPE"
    exit
fi

delete