#!/bin/bash
set -e

echo Authenticating with GCloud...
gcloud auth activate-service-account --key-file=/secrets/service-account.json

echo Starting Teamcity Agent...
/run-services.sh