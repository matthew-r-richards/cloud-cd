# cloud-cd
Jenkins or Teamcity Continuous Deployment (CD) entirely in the cloud - running on and deploying to Google Container Engine (GKE).

## Objectives
Create a Kubernetes cluster on GKE with the following characteristics:
* CD server applications deployed in the cluster and accessible via a public IP
* CD build agents are provisioned dynamically and managed within the kubernetes cluster itself
* Application(s) are built by these agents and then deployed to the same cluster - triggered manually or by VCS commits

## Getting Started
### Setting up the cluster
A setup BASH script has been included in the root of the repository, `create-cluster.sh`.
This can be run using the following command:

`create-cluster.sh [jenkins/teamcity] [path-to-service-account-key.json]`

For example, to create a jenkins cluster using the service account file `service-account.json`, run 

`create-cluster.sh jenkins service-account.json`

The creation process will take several minutes. At the end of it, you will be given the IP address to access the UI on. Note that it might take 10-15 minutes for the Load Balancer configuration to be replicated, so the service may not be accessible immediately.

#### Configuration
The configuration is defined in `scripts/config.sh`. The only value that must be set is the `PROJECT_ID` value - set this to the ID of the Google Cloud Project where you want to create the cluster.

The rest of the default configuration should be sufficient for most purposes, however see [here] for more details on all configuration options.

#### Service Account
A Google Cloud service account key file (in JSON format) is required in order for the script to carry out actions using the [Google Cloud SDK](https://cloud.google.com/sdk/):
* [Create the service account](https://cloud.google.com/iam/docs/creating-managing-service-accounts#creating_a_service_account), granting it the `Editor` role
* [Obtain the service account key](https://cloud.google.com/iam/docs/creating-managing-service-account-keys) and store the downloaded JSON file in a suitable location
### Setting up Jenkins
### Setting up Teamcity
## Continuous Deployment
### Jenkins
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
* Kubernetes namespace - logical separation for all kubernetes entities related to the CD server
* Kubernetes services
* Kubernetes deployment
* Kubernetes secret - defines the SSL certificate to be used in the ingress controller
* Kubernetes ingress controller - implicitly creates a GCE Load Balancer using a self-signed SSL certificate defined in the secret, with traffic restricted to HTTPS only. SSL termination is performed (i.e. cluster traffic is HTTP).

The following configuration variables are contained in the `utils/config.sh` script:
* Common
* `PROJECT_ID` - the Google Cloud project ID where the cluster will be created
* `CLUSTER_ZONE` - the Google Cloud [zone](https://cloud.google.com/compute/docs/regions-zones/) where the cluster will be created
* `CLUSTER_NODE_COUNT` - the number of worker nodes in the cluster
* `CLUSTER_NODE_TYPE` - the [machine type](https://cloud.google.com/compute/docs/machine-types) for the worker nodes
* Jenkins
* `JENKINS_MASTER_IMAGE` - see [Updating image]
* Teamcity
## Updating the Jenkins or Teamcity Images
Change config variables AND image names in the yaml files
## Acknowledgements
Ref google pages
