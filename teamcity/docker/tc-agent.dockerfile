FROM jetbrains/teamcity-agent:2017.1.5

ENV CLOUDSDK_CORE_DISABLE_PROMPTS 1
ENV PATH /opt/google-cloud-sdk/bin:$PATH

# Get GCloud SDK
RUN curl https://sdk.cloud.google.com | bash && mv /root/google-cloud-sdk /opt

# Install kubectl
RUN gcloud components install kubectl

# Install any other dependencies
RUN apt-get update -y \
    && apt-get install -y jq