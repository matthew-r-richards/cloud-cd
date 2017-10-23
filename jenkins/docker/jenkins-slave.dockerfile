FROM jenkins/jnlp-slave:3.7-1

ENV CLOUDSDK_CORE_DISABLE_PROMPTS 1
ENV PATH /opt/google-cloud-sdk/bin:$PATH

USER root

# Get GCloud SDK
RUN curl https://sdk.cloud.google.com | bash && mv google-cloud-sdk /opt

# Install kubectl
RUN gcloud components install kubectl

# Install any other dependencies
RUN apt-get update -y \
    && apt-get install -y jq