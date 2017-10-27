# Formatting constants
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# usage - pushToGCR [image-tag]
pushToGCR() {
    echo "$BOLD---- Pushing to Google Container Registry$NORMAL"
    gcloud docker -- push $1
}

# usage - buildJenkinsImages [master-image-tag] [slave-image-tag]
buildJenkinsImages() {
    echo "$BOLD---- Build Jenkins Master Docker Image$NORMAL"
    docker build -t $1 -f ./jenkins/docker/jenkins-master.dockerfile ./jenkins/docker
    pushToGCR $1
    echo "$BOLD---- Jenkins Master Image name is $1$NORMAL"

    echo "$BOLD---- Build Jenkins Slave Docker Image$NORMAL"
    docker build -t $2 -f ./jenkins/docker/jenkins-slave.dockerfile ./jenkins/docker
    pushToGCR $2
    echo "$BOLD---- Jenkins Slave Image name is $2$NORMAL"
}

# usage - buildTeamcityImages [master-image-tag] [slave-image-tag]
buildTeamcityImages() {
    echo "$BOLD---- Build Teamcity Server Docker Image$NORMAL"
    docker build -t $1 -f ./teamcity/docker/tc-server.dockerfile ./teamcity/docker
    pushToGCR $1
    echo "$BOLD---- Teamcity Server Image name is $1$NORMAL"

    echo "$BOLD---- Build Teamcity Agent Docker Image$NORMAL"
    docker build -t $2 -f ./teamcity/docker/tc-agent.dockerfile ./teamcity/docker
    pushToGCR $2
    echo "$BOLD---- Teamcity Agent Image name is $2$NORMAL"
}

# usage - updateJenkinsDeployment [master-image-tag]
updateJenkinsDeployment() {
    echo "$BOLD---- Updating Jenkins K8S Deployment with Master Image Tag $1$NORMAL"
    sed s#%MASTER_IMAGE%#$1# <./jenkins/k8s/deployment_template_jenkins.yaml >./jenkins/k8s/deployment_jenkins.yaml
}

# usage - updateTeamcityDeployment [server-image-tag] [agent-image-tag]
updateTeamcityDeployment() {
    echo "$BOLD---- Updating Teamcity K8S Deployment with Server Image Tag $1$NORMAL"
    echo "$BOLD---- Updating Teamcity K8S Deployment with Agent Image Tag $2$NORMAL"
    sed -e s#%SERVER_IMAGE%#$1# \
        -e s#%AGENT_IMAGE%#$2# \
        <./teamcity/k8s/deployment_template_teamcity.yaml >./teamcity/k8s/deployment_teamcity.yaml
}