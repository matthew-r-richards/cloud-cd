#!/bin/bash
set -e

echo Copying plugins...
cp -r /usr/share/tc/plugins /data/teamcity_server/datadir

echo Starting Teamcity Server...
/run-services.sh