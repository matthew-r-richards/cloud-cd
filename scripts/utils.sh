# usage - commandExists [command-name]
commandExists() {
  if [[ ! `command -v $1` ]]; then
    echo "'$1' Application not found"
    exit
  fi
}

# usage - gcloudLogin [path-to-key-file]
gcloudLogin() {
    echo "$BOLD---- Connecting as service account using the key file $1$NORMAL"
    gcloud auth activate-service-account --key-file=$1
}

# usage - enableApi [api-name]
enableApi() {
    if [[ ! -z $(gcloud service-management list --enabled 2> /dev/null | grep $1) ]]; then
        echo "$1 already enabled"
    else
        echo "Enabling $1"
        gcloud service-management enable $1
    fi
}

# usage - checkApis
checkApis() {
    echo "$BOLD---- Checking Google APIs for Project$NORMAL"
    enableApi compute.googleapis.com
    enableApi container.googleapis.com
    enableApi containerregistry.googleapis.com
}

# usage - networkExists [network-name]
networkExists() {
    [[ ! -z $(gcloud compute networks list 2> /dev/null | grep $1) ]]
}

# usage - clusterExists [cluster-name]
clusterExists() {
    [[ ! -z $(gcloud container clusters list 2> /dev/null | grep $1) ]]
}

# usage - diskExists [disk-name]
diskExists() {
    [[ ! -z $(gcloud compute disks list 2> /dev/null | grep $1) ]]
}

# usage - k8sNamespaceExists [namespace]
k8sNamespaceExists() {
    [[ ! -z $(kubectl get namespaces 2>&1 | grep $1) ]]
}

# usage - k8sTlsSecretExists [namespace] [secret-name]
k8sTlsSecretExists() {
    [[ ! -z $(kubectl get secrets -n $1 2>&1 | grep $2) ]]
}