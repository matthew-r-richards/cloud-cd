if [[ -z $1 ]]; then
    echo Usage get-jenkins-initial-password.sh [kubernetes namespace]
    exit
fi

K8S_NAMESPACE=$1
POD_NAME=$(kubectl get pod -n $K8S_NAMESPACE --selector=app=master -o jsonpath="{.items[0].metadata.name}")

if [[ -z $POD_NAME ]]; then
    echo "Jenkins master pod not found in $K8S_NAMESPACE namespace"
    exit
fi

INITIAL_PWD=$(kubectl exec -n $K8S_NAMESPACE $POD_NAME cat /var/jenkins_home/secrets/initialAdminPassword)
$(echo $INITIAL_PWD > ./initialAdminPassword)
echo "---- Initial Admin Password is $INITIAL_PWD and is also saved in ./initialAdminPassword.txt"