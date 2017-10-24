PROJECT_ID=jenkins-continuous-deployment
CLUSTER_ZONE=europe-west3-a
CLUSTER_NODE_COUNT=1
CLUSTER_NODE_TYPE=n1-standard-2
# Persistent Disk for data / config storage
PDISK_SIZE=10GB

# Jenkins configuration
JENKINS_CLUSTER_NAME=jenkins-cd
JENKINS_MASTER_IMAGE=jenkins-master:2.85
JENKINS_SLAVE_IMAGE=jenkins-slave:3.7-1

# Teamcity configuration
TEAMCITY_CLUSTER_NAME=teamcity-cd
TEAMCITY_SERVER_IMAGE=tc-server:2017.1.5
TEAMCITY_AGENT_IMAGE=tc-agent:2017.1.5