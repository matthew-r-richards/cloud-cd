# cloud-cd

Jenkins or Teamcity Continuous Deployment entirely in the cloud - running on and deploying to Google Container Engine.

Abbreviations used:

* CD: Continuous Deployment
* GKE: Google Container Engine
* GCR: Google Container Registry (docker image repository)
* GCE: Google Compute Engine
* K8S: Kubernetes
* VCS: Version Control System (e.g. Git)

Jenkins and Teamcity both have a master-slave architecture for builds, there is a central build server (the master) and this manages one or more build agents (the slaves) to perform builds. Jenkins uses the terminology `master` and `slave`, whereas Teamcity uses `server` and `agent`. In the following instructions, `master / server` can be used interchangeably, as can `slave / agent`.

## Objectives

We want to create a K8S cluster on GKE with the following characteristics:

* CD server applications deployed in the cluster and accessible via a public IP
* CD build agents are provisioned dynamically and managed within the kubernetes cluster itself
* Application(s) are built by these agents and then deployed to the same cluster - triggered manually or by VCS commits

## Pre-requisites

The following binaries need to be installed on the machine where the script will be executed:
* `gcloud` - [instructions](https://cloud.google.com/sdk/downloads)
* `kubectl` - `gcloud components install kubectl` or [instructions](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* `openssl` - install using package manager
* `docker` - [instructions](https://docs.docker.com/engine/installation/#supported-platforms) (Docker CE)

### Project

A Google Cloud project is required in order to contain the cluster and all the related objects. After [creating a project](https://cloud.google.com/resource-manager/docs/creating-managing-projects), note down the `Project ID` (which may be different to the `Project Name`) for use in the setup script.

### Service Account

A Google Cloud service account is required in order for the cluster setup script to carry out actions using the [Google Cloud SDK](https://cloud.google.com/sdk/). The account can be created and the required key file (in JSON format) obtained as follows:

1) [Create the service account](https://cloud.google.com/iam/docs/creating-managing-service-accounts#creating_a_service_account) within the project, granting the account the `Editor` role
1) [Obtain the service account key](https://cloud.google.com/iam/docs/creating-managing-service-account-keys) and store the downloaded JSON file in a suitable location

## Getting Started

### Setting up the cluster

A setup BASH script has been included in the root of the repository, `create-cluster.sh`.
This can be run using the following command:

`create-cluster.sh [jenkins/teamcity] [project-id] [path-to-service-account-key.json]`

The service account key file and the Project ID must be obtained before running the script, see *Pre-requisites*.

For example, to create a jenkins cluster in the `jenkins-cd` project, using the service account file `service-account.json`:

1) Create the service account and export the key to `service-account.json` as described in *Pre-requisites » Service Account*
1) Run `create-cluster.sh jenkins jenkins-cd service-account.json`

The creation process will take several minutes. At the end of it, you will be given the IP address to access the system on.

**Note:** it might take 10-15 minutes for the Load Balancer configuration to be replicated, therefore the system may not be accessible immediately.

As part of the script process, the local configuration for the [Kubernetes CLI](https://kubernetes.io/docs/user-guide/kubectl-overview/), `kubectl`, will be set so that it is authenticated for the newly created cluster - `kubectl` can be used from the terminal as normal, with commands executed against the cluster.

#### Configuration

The cluster configuration is defined in `scripts/config.sh`. The default configuration should be sufficient for most purposes, however see *Configuration Details* for details on all configuration options.

### Setting up Jenkins within the Cluster

Once the ingress configuration is complete, going to the Jenkins URL should take you to the initial setup:

1) You will be asked for the initial admin password, which is given in the output from the `create-cluster.sh` script and is also stored in `jenkins/initialAdminPassword`.
1) The default option to 'Install suggested plugins' is probably sufficient for most use cases. To include additional plugins when the Jenkins master image is built, enter the plugin names as line-separated values in the `jenkins/docker/plugins.txt` file. Any changes to this file will require the `create-cluster.sh` script to be re-run to re-deploy the updated `jenkins-master` image (it is recommended to increment the version number as well, see *Updating the Jenkins or Teamcity Images*).
1) Create the 'First Admin User' as required

Once the initial setup is complete, the remaining steps are:

1) Configure the [Kubernetes plugin](https://wiki.jenkins.io/display/JENKINS/Google+Source+Plugin) to pick up the kubernetes cluster service account credentials (allows use of `kubectl` commands in the build without any further authentication) - [instructions](https://cloud.google.com/solutions/configuring-jenkins-container-engine#adding_kubernetes_credentials)
1) Configure the [Google Authenticated Source plugin](https://wiki.jenkins.io/display/JENKINS/Google+Source+Plugin) to pick up the Google cloud service account credentials from metadata (allows use of `gcloud` commands in the build without any further authentication) - [instructions](https://cloud.google.com/solutions/configuring-jenkins-container-engine#adding_google_service_account_credentials)
1) Configure the kubernetes plugin to create Jenkins build executors from the `jenkins-slave` image produced as part of the `create-cluster.sh` script - [instructions](https://cloud.google.com/solutions/configuring-jenkins-container-engine#configuring_the_build_executors)  
  **Note:** use the full `gcr.io/[$PROJECT_ID]/[JENKINS_SLAVE_IMAGE]` repository path when specifying the docker image to use. This is output during the `create-cluster.sh` script execution
1) (Optionally) Configure the slave pod template created in step *3* to have access to the kubernetes cluster docker daemon - see *Docker in the Build Process*

At this point, Jenkins is ready for builds to be defined. These builds will run in one or more pods in the cluster, based on the template defined in step *3* above.

### Setting up Teamcity within the Cluster

Once the ingress configuration is complete, going to the Teamcity URL should take you to the initial setup:

1) Click 'Proceed' on the information screens about the Teamcity data directory and the database type (internal is sufficient for these purposes) and then wait for the initialisation process to complete (this may take a while due to the server pod CPU limit)
1) Accept the license agreement
1) Create an Administrator account as required

To include additional plugins when the Teamcity server image is built, place the downloaded plugin `.zip` files into the `teamcity/docker/plugins` folder. Any changes to the contents of this folder will require the `create-cluster.sh` script to be re-run to re-deploy the updated `tc-server` image (it is recommended to increment the version number as well, see *Updating the Jenkins or Teamcity Images*).

Once the initial setup is complete, the remaining steps are:

1) In **Server Admininstration > Global Settings**, configure the **Server URL** to be `http://teamcity:8111`. This allows the teamcity agents to connect to the teamcity service on the internally resolved service name. The default value is the external IP (i.e. the ingress IP) - with self-signed SSL certificates (as we have here), the agents will be unable to establish a connection.
1) Create a Teamcity project to contain the build definitions
1) In the administrator panel for the project, go to 'Cloud Profiles'.
1) Setup the [Team City Kubernetes plugin](https://github.com/JetBrains/teamcity-kubernetes-plugin) by clicking on 'Create new profile' and entering the following configuration:

    **Profile name** - e.g. `kubernetes`

    **Cloud type** - `Kubernetes`

    **Kubernetes API server URL** - `https://kubernetes.default`

    **Kubernetes Namespace** - `teamcity` (click on the icon to pick from available namespaces)

    **Authentication Strategy** - `Default Service Account`

    **Agent images** - Add an image, with **Pod Specification** set to `Use pod template from deployment` and the **Deployment name** as `tc-agent` (click on the icon to pick from available deployments). Select `<project pool>` for the **Agent pool**.

At this point, Teamcity is ready for build steps to be defined. These builds will run in one or more pods in the cluster, based on the template defined in step *3* above.

### Docker in the Build Process

The Jenkins/Teamcity slaves/agents are running within the K8S cluster. For our CD process, we need to make use of docker to build the application image (which will be deployed to the same cluster).

It is possible to install docker within the slave/agent image and use it this way, however this means that each time a slave/agent pod is killed, the docker image cache would be lost (and images would need to be re-downloaded on a subsequent build).

So the best solution is to re-use the docker daemon from the cluster itself within the slave/agent pods running on it.

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

The continuous deployment process we are aiming for is:

1) Build is triggered by VCS commit (or manually)
1) Create the slave/agent pod to use during the build - subsequent steps all run within this pod
1) Pull changes from VCS
1) Build the code, run tests (unit, integration, automated acceptance etc.)
1) Build docker image(s)
1) Push this image to the Google Cloud Repository
1) Update the K8S deployment with the details of the new image (triggering a rolling update)

In the following sections, we will refer to Jenkins/Teamcity as the *CD server*, and the actual code being built and deployed by the CD process as the *application*.

In the simplest case, we are deploying the application(s) to the same cluster that the CD server is running on. This allows us to make use of the kubernetes and Google credentials supplied automatically to the slave/agent pods, i.e. we don't need to authenticate for a different service account / cluster.

We use [kubernetes namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) to provide 'virtual clusters' and logically separate each of the applications in the cluster. This does mean that the CD server and the application are sharing the same cluster resources and could choke each other if resources are not managed well. Some techniques for resource management are:

* setting pod [resource limits](https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/) (CPU and/or memory)
* setting limits for the number of CD slave pods (i.e. the number of simultaneous builds supported)
* setting sensible replica limits if using a [horizontal pod autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) within the application
* setting [resource quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/) for the namespaces to limit total resource usage (CPU and/or memory) within that namespace

If you prefer the CD server and deployed application to exist on different clusters, see *Deploying to another cluster*.

### Jenkins

The Jenkins build can be created using any of the built-in types (e.g. freestyle, pipeline, multi-branch pipeline). Using the pipeline or multi-branch pipeline options allows use of a `Jenkinsfile`, moving the build configuration into your VCS.

A sample `Jenkinsfile` can be found for the `sample-app` application - `sample-app/Jenkinsfile`. Breaking this down for a `master` branch commit:
1) `sh("docker build -t ${imageTag} .")` - build the docker image, where `imageTag` is based on the branch name and jenkins build number
1) `sh("docker run ${imageTag} go test")` - run the image in a container to execute some tests
1) `sh("gcloud docker -- push ${imageTag}")` - push the docker image to GCR
1) `sh("kubectl get ns production || kubectl create ns production")` - create the K8S `production` namespace if it doesn't exist
1) `sh("sed -i.bak 's#gcr.io/cloud-solutions-images/gceme:1.0.0#${imageTag}#' ./k8s/production/*.yaml")` - update the application deployment with the new `imageTag`, see step *1*
1) `sh("kubectl --namespace=production apply -f k8s/services/")` - apply the application service definitions
1) `sh("kubectl --namespace=production apply -f k8s/canary/")` - apply the application deployment definitions (which have been updated with the new image)

This sample also has an example of the 'Canary' build pattern, whereby changes to the `canary` branch are built and deployed to a small number of pods in the `production` namespace for testing with a limited set of users. This is done using a separate deployment for the canary pods, meaning they can be updated separately to the rest of the pods in the `production` namespace. Once approved, the `canary` branch can be merged back into `master`, which will trigger a deployment to the rest of the `production` pods.

Commits to branches that aren't `canary` or `master` (i.e. development branches) will be deployed to a namespace of the same name and will not be exposed externally (you have to use `kubectl proxy` to create a proxy to the service on the cluster).

As mentioned in *Docker in the Build Process*, the docker daemon can be mounted from the host kubernetes cluster. This allows the docker commands in the `Jenkinsfile` to be run without docker installed in the `jenkins-slave` image. It also means that images required for building from the `Dockerfiles` will be cached in the cluster rather than being lost each time a slave pod is terminated.

### Teamcity

The Teamcity build can be created using a standard project and build definition. Teamcity does not have a `Jenkinsfile` equivalent, therefore all of the build steps need to be configured within the Teamcity UI itself.

Using the same sample application as the *Jenkins* example above, the Teamcity build steps would be almost exactly the same, with the commands within the Jenkins `sh("...")` blocks running as `Command Line` steps.

As mentioned in *Docker in the Build Process*, the docker daemon can be mounted from the host kubernetes cluster. This allows the docker commands in the build steps to be run without docker installed in the `jenkins-slave` image. It also means that images required for building from the `Dockerfiles` will be cached in the cluster rather than being lost each time a slave pod is terminated.

### Deploying to another cluster

By default, the build agent pod has access to the current cluster via a kubernetes service account (this is handled by the Jenkins/Teamcity plugins). In order to deploy to another cluster, the following may be required:

* Authenticate with a different Google Cloud service account (if the current service account does not have access to the other cluster). This requires a service account key file as described in *Pre-requisities » Service Account*. The service account key file should be provided as a [kubernetes secret](https://kubernetes.io/docs/concepts/configuration/secret/), as demonstrated by the `svc-account` secret created by `create-cluster.sh` and its use in the `tc-agent` deployment:  
  `gcloud auth activate-service-account [path-to-service-account-key.json]`

* Authenticate `kubectl` for the other cluster  
  `gcloud container clusters get-credentials --zone [zone] --project [project-id]`

After these steps, the build process can make use of the `gcloud` and `kubectl` tools which will be authenticated for the other project/cluster.

## Configuration Details

This script creates the following:

* Google Compute Engine (GCE) network - logical separation for all traffic related to the CD server
* GCE persistent disk - persistent storage for the CD server configuration data (i.e. it persists between pod restarts)
* GKE cluster
* K8S namespace - logical separation for all kubernetes entities related to the CD server
  * K8S [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
    * JENKINS - `jenkins/k8s/service_jenkins.yaml` - `jenkins-ui` (`NodePort` exposing `jenkins` pod via the Ingress) **AND** `jenkins-discovery` (`ClusterIP` to allow slaves to connect to the `jenkins` master pod)
    * TEAMCITY - `teamcity/k8s/service_teamcity.yaml` - `teamcity` (`NodePort` exposing `tc-server` pod via the Ingress, also allows agents to connect)
  * K8S [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
    * JENKINS - `jenkins/k8s/deployment_jenkins.yaml` - `jenkins` (single master pod)
    * TEAMCITY - `teamcity/k8s/deployment_teamcity.yaml` - `tc-server` (single server pod) **AND** `tc-agent` (0 replicas, used as a template for Teamcity agents)
  * K8S [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)
    * `tls` - defines the SSL certificate to be used in the ingress controller
    * TEAMCITY - `svc-account` - makes the service account key file available for use in `tc-agent` pods
  * K8S [TLS Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) - implicitly creates a GCE Load Balancer using a self-signed SSL certificate defined in the secret, with traffic restricted to HTTPS only. SSL termination is performed (i.e. cluster traffic is HTTP)
    * JENKINS - `jenkins/k8s/ingress_jenkins.yaml`
    * TEAMCITY - `teamcity/k8s/ingress_teamcity.yaml`

The following configuration variables are contained in the `utils/config.sh` script:

* Common
  * `CLUSTER_ZONE` - the Google Cloud [zone](https://cloud.google.com/compute/docs/regions-zones/) where the cluster will be created
  * `CLUSTER_NODE_COUNT` - the number of worker nodes in the cluster
  * `CLUSTER_NODE_TYPE` - the [machine type](https://cloud.google.com/compute/docs/machine-types) for the worker nodes
* Jenkins-specific
  * `JENKINS_CLUSTER_NAME` - the name of the GKE cluster for Jenkins
  * `JENKINS_MASTER_IMAGE` - see *Updating the Jenkins or Teamcity Images*
  * `JENKINS_SLAVE_IMAGE` - see *Updating the Jenkins or Teamcity Images*
* Teamcity-specific
  * `TEAMCITY_CLUSTER_NAME` - the name of the GKE cluster for Teamcity
  * `TEAMCITY_SERVER_IMAGE` - see *Updating the Jenkins or Teamcity Images*
  * `TEAMCITY_AGENT_IMAGE` - see *Updating the Jenkins or Teamcity Images*

## Updating the Jenkins or Teamcity Images

By default, kubernetes uses an image pull policy of `IfNotPresent`, which means that if the image has already been pulled by kubernetes, it will never be fetched again as long as the image tag is unchanged. This means that if you make any changes to the image (or files included in it) but don't update the image tag, the changes won't be picked up by the kubernetes deployments.

One way of avoiding this is to set the `imagePullPolicy` for the container(s) to `Always`.

However, a better solution is to have a versioned image tag and always increment this version when the image is updated. This way the image will always be pulled when it is updated (as the tag has changed) and you will be able to roll back to previous versions of the image if necessary.

See [here](https://kubernetes.io/docs/concepts/configuration/overview/#container-images) for more discussion.

The Jenkins and Teamcity image names (including a versioned tag) are set using the `JENKINS_[MASTER/SLAVE]_IMAGE` and `TEAMCITY_[SERVER/AGENT]_IMAGE` config variables (see *Configuration Details*) respectively. These values are inserted into the kubernetes deployments by the `create-cluster.sh` script, so that they pick up the docker images built using the same tag.

## Costs

Using the [Google Pricing Calculator](https://cloud.google.com/products/calculator/) the following values give an indication of the cost of running a Container Engine cluster.

As of 25/10/17 in the `europe-west2` region (London) a single node (`n1-standard-2`) cluster with an additional 10GB persistent disk (for the CD configuration) would cost **$0.086 / hour** or **$14.50 / week** (24/7 running).

Each additional `n1-standard-2` node in the cluster will cost **$0.086 / hour** (persistent disk cost per hour is negligible).

After 5 nodes, there is a charge for the container engine service, which would add **$0.15 / hour**.

## Acknowledgements

The inspiration for this project comes from the following Google articles:

* [Jenkins on Container Engine Tutorial](https://cloud.google.com/solutions/jenkins-on-container-engine-tutorial)
* [Jenkins on Container Engine Best Practices](https://cloud.google.com/solutions/jenkins-on-container-engine)
* [Configuring Jenkins for Container Engine](https://cloud.google.com/solutions/configuring-jenkins-container-engine)

