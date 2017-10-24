PROJECT_ID=jenkins-continuous-deployment
CLUSTER_ZONE=europe-west3-a
CLUSTER_NODE_COUNT=1
CLUSTER_NODE_TYPE=n1-standard-2
# Persistent Disk for data / config storage
PDISK_SIZE=10GB

# Jenkins configuration
JENKINS_MASTER_IMAGE=jenkins-master:2.85
JENKINS_SLAVE_IMAGE=jenkins-slave:3.7-1
JENKINS_NETWORK_NAME=jenkins
JENKINS_CLUSTER_NAME=jenkins-cd
JENKINS_PDISK_NAME=jenkins-home
JENKINS_K8S_NAMESPACE=jenkins
JENKINS_INGRESS_NAME=jenkins-ingress

# Teamcity configuration
TEAMCITY_SERVER_IMAGE=tc-server:2017.1.5
TEAMCITY_AGENT_IMAGE=tc-agent:2017.1.5
TEAMCITY_NETWORK_NAME=teamcity
TEAMCITY_CLUSTER_NAME=teamcity-cd
TEAMCITY_PDISK_NAME=teamcity-data
TEAMCITY_K8S_NAMESPACE=teamcity
TEAMCITY_INGRESS_NAME=teamcity-ingress