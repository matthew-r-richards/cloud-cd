# cloud-cd
Jenkins or Teamcity Continuous Deployment entirely in the cloud - running on and deploying to Google Container Engine.

Abbreviations:
* CD: Continuous Deployment
* GKE: Google Container Engine
* GCE: Google Compute Engine
* K8S: Kubernetes

## Objectives
We want to create a K8S cluster on GKE with the following characteristics:
* CD server applications deployed in the cluster and accessible via a public IP
* CD build agents are provisioned dynamically and managed within the kubernetes cluster itself
* Application(s) are built by these agents and then deployed to the same cluster - triggered manually or by VCS commits

## Getting Started
### Setting up the cluster
A setup BASH script has been included in the root of the repository, `create-cluster.sh`.
This can be run using the following command:

`create-cluster.sh [jenkins/teamcity] [path-to-service-account-key.json]`

The service account key must be obtained and the Project ID set before running the script.

For example, to create a jenkins cluster in the `jenkins-cd` project, using the service account file `service-account.json`:
* create the service account and export the key to `service-account.json` as described in *Service Account*
* in the `scripts/config.sh` script, set `PROJECT_ID=jenkins-cd`
* run `create-cluster.sh jenkins service-account.json`

The creation process will take several minutes. At the end of it, you will be given the IP address to access the system on.
  
**Note:** it might take 10-15 minutes for the Load Balancer configuration to be replicated, so the system may not be accessible immediately.

#### Service Account
A Google Cloud service account key file (in JSON format) is required in order for the script to carry out actions using the [Google Cloud SDK](https://cloud.google.com/sdk/):
* [Create the service account](https://cloud.google.com/iam/docs/creating-managing-service-accounts#creating_a_service_account), granting it the `Editor` role
* [Obtain the service account key](https://cloud.google.com/iam/docs/creating-managing-service-account-keys) and store the downloaded JSON file in a suitable location

#### Configuration
The cluster configuration is defined in `scripts/config.sh`. The only value that is specific to a user is the `PROJECT_ID` value - set this to the ID of the Google Cloud Project where you want to create the cluster.

The rest of the default configuration should be sufficient for most purposes, however see *Configuration Details* for details on all configuration options.

### Setting up Jenkins within the Cluster
Once the ingress configuration is complete, going to the Jenkins URL should take you to the initial setup.

You will be asked for the initial admin password, which is given in the output from the `create-cluster.sh` script and is also stored in `jenkins/initialAdminPassword`.
### Setting up Teamcity within the Cluster

### 'Docker-in-Docker'
The Jenkins/Teamcity slaves/agents are running within the K8S cluster. For our CD process, we need to make use of docker to build the application image (which will be deployed to the same cluster).

It is possible to install docker within the slave/agent image and use it this way, however this means that each time a slave/agent pod is killed, the docker image cache would be lost (and images would need to be re-downloaded on the subsequent build).

So the best solution is 'docker-in-docker' - reusing the docker daemon from the cluster itself within the slave/agent pods running on it.

This is done as follows:
* Jenkins
  * add the following volumes to the slave image definition:
    * `/usr/bin/docker:/usr/bin/docker` (Docker binary)
    * `/var/run/docker.sock:/var/run/docker.sock` (Docker socket)
* Teamcity
  * the `volumeMounts` and `volumes` to map the Docker binary and socket (as above) are already included in the `tc-agent` definition in `teamcity/k8s/deployment_teamcity.yaml`


### Teardown
The `delete-cluster.sh` script can be run to remove the cluster and all of the related GCE objects (firewall rules, load balancers, persistent disks etc.). The script uses the `.lastconfig` file written by the `create-cluster.sh` script to determine what objects need to be deleted.

**Note:** if you have the CD server deploying applications to the same cluster as it is running on, these applications will be lost when the cluster is deleted. The script will only delete objects outside of the cluster that are related to the CD server, i.e. any disks, firewall rules, load balancers etc. that are related to the deployed application, not the CD server, will remain. These will need to be removed separately.

## Continuous Deployment
The continuous deployment process can be characterised as:
* build is triggered by VCS commit (or manually)
* create the slave/agent pod to use during the build
* within this pod:
  * pull changes from VCS
  * build the code, run tests (unit, integration, automated acceptance etc.)
  * build a docker image
  * push this image to the Google Cloud Repository
  * update the K8S deployment with the details of the new image (triggering a rolling update)

### Jenkins
A sample `Jenkinsfile` can be found for the `sample-app` application - `sample-app/Jenkinsfile`.
This sample also has an example of using a 'Canary' build process, whereby changes to the `Canary` branch are built and deployed to a small number of pods in the production environment for testing with a limited set of users. Once approved, the `Canary` branch can be merged back into `Master`, which will trigger a deployment to the rest of the production pods.

As mentioned in *Continuous Deployment*, the docker daemon 

### Teamcity

### Deploying to another cluster
By default, the build agent pod has access to the current cluster via a kubernetes service account (this is handled by the Jenkins/Teamcity plugins). In order to deploy to another cluster, the following may be required:
* Authenticate with a different Google Cloud service account (if the current service account does not have access to the other cluster)  
  `gcloud auth activate-service-account [path-to-service-account-key.json]`

* Authenticate `kubectl` for the other cluster  
  `gcloud container get-credentials`

After these steps, the build steps can make use of the `gcloud` and `kubectl` tools for the new project/cluster.

## Configuration Details
This script creates the following:
* Google Compute Engine (GCE) network - logical separation for all traffic related to the CD server
* GCE persistent disk - persistent storage for the CD server configuration data (i.e. it persists between pod restarts)
* GKE cluster
* K8S namespace - logical separation for all kubernetes entities related to the CD server
  * K8S [Service](https://kubernetes.io/docs/concepts/services-networking/service/) (`jenkins/k8s/service_jenkins.yaml` **OR** `teamcity/k8s/service_teamcity.yaml`)
    * `jenkins-ui` (`NodePort` exposing `jenkins` pod via the Ingress) **AND** `jenkins-discovery` (`ClusterIP` to allow slaves to connect to the `jenkins` master pod) **OR**
    * `teamcity` (`NodePort` exposing `tc-server` pod via the Ingress, also allows agents to connect)
  * K8S [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) (`jenkins/k8s/deployment_jenkins.yaml` **OR** `teamcity/k8s/deployment_teamcity.yaml`)
    * `jenkins` (single master pod) **OR**
    * `tc-server` (single master pod) **AND** `tc-agent` (0 replicas, used as a template for Teamcity agents)
  * K8S [Secret](https://kubernetes.io/docs/concepts/configuration/secret/) - defines the SSL certificate to be used in the ingress controller
  * K8S [TLS Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) (`jenkins/k8s/ingress_jenkins.yaml` **OR** `teamcity/k8s/ingress_teamcity.yaml`) - implicitly creates a GCE Load Balancer using a self-signed SSL certificate defined in the secret, with traffic restricted to HTTPS only. SSL termination is performed (i.e. cluster traffic is HTTP).

The following configuration variables are contained in the `utils/config.sh` script:
* Common
  * `PROJECT_ID` - the Google Cloud project ID where the cluster will be created
  * `CLUSTER_ZONE` - the Google Cloud [zone](https://cloud.google.com/compute/docs/regions-zones/) where the cluster will be created
  * `CLUSTER_NODE_COUNT` - the number of worker nodes in the cluster
  * `CLUSTER_NODE_TYPE` - the [machine type](https://cloud.google.com/compute/docs/machine-types) for the worker nodes
* Jenkins
  * `JENKINS_CLUSTER_NAME` - the name of the GKE cluster for Jenkins
  * `JENKINS_MASTER_IMAGE` - see *Updating the Jenkins or Teamcity Images*
  * `JENKINS_SLAVE_IMAGE` - see *Updating the Jenkins or Teamcity Images*
* Teamcity
  * `TEAMCITY_CLUSTER_NAME` - the name of the GKE cluster for Teamcity
  * `TEAMCITY_SERVER_IMAGE` - see *Updating the Jenkins or Teamcity Images*
  * `TEAMCITY_AGENT_IMAGE` - see *Updating the Jenkins or Teamcity Images*

## Updating the Jenkins or Teamcity Images
Change config variables AND image names in the yaml files

## Acknowledgements
Ref google pages
