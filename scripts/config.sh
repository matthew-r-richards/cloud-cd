CLUSTER_ZONE=europe-west2-a
CLUSTER_NODE_COUNT=1
CLUSTER_NODE_TYPE=n1-standard-2
# Persistent Disk for data / config storage
PDISK_SIZE=10GB

# Jenkins configuration
JENKINS_CLUSTER_NAME=jenkins-cd
JENKINS_MASTER_IMAGE=jenkins-master:1.0.0
JENKINS_SLAVE_IMAGE=jenkins-slave:1.0.0

# Teamcity configuration
TEAMCITY_CLUSTER_NAME=teamcity-cd
TEAMCITY_SERVER_IMAGE=tc-server:1.0.0
TEAMCITY_AGENT_IMAGE=tc-agent:1.0.0