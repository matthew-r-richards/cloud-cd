FROM jetbrains/teamcity-server:2017.1.5

COPY ./plugins /usr/share/tc/plugins
COPY ./start-teamcity.sh /start-teamcity.sh

# Copy the plugins into the data directory at runtime, otherwise
# they will be wiped when the data volume is mounted
CMD ["/start-teamcity.sh"]