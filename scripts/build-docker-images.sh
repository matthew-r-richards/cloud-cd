# Formatting constants
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# usage - buildJenkinsImages [master-image-tag] [slave-image-tag]
buildJenkinsImages() {
    echo "$BOLD---- Build Jenkins Master Docker Image$NORMAL"
    docker build -t $1 -f ./jenkins/docker/jenkins-master.dockerfile ./jenkins/docker
    pushToGCR $1
    echo "$BOLD---- Image name is $1$NORMAL"

    echo "$BOLD---- Build Jenkins Slave Docker Image$NORMAL"
    docker build -t $2 -f ./jenkins/docker/jenkins-slave.dockerfile ./jenkins/docker
    pushToGCR $2
    echo "$BOLD---- Image name is $2$NORMAL"
}

# usage - buildTeamcityImages [master-image-tag] [slave-image-tag]
buildTeamcityImages() {
    echo "$BOLD---- Build Teamcity Server Docker Image$NORMAL"
    docker build -t $1 -f ./teamcity/docker/tc-server.dockerfile ./teamcity/docker
    pushToGCR $1
    echo "$BOLD---- Image name is $1$NORMAL"

    echo "$BOLD---- Build Teamcity Agent Docker Image$NORMAL"
    docker build -t $2 -f ./teamcity/docker/tc-agent.dockerfile ./teamcity/docker
    pushToGCR $2
    echo "$BOLD---- Image name is $2$NORMAL"
}

# usage - pushToGCR [image-tag]
pushToGCR() {
    echo "$BOLD---- Pushing to Google Container Registry$NORMAL"
    gcloud docker -- push $1
}