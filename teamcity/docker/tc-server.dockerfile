FROM jetbrains/teamcity-server:2017.1.5

COPY ./plugins /usr/share/tc/plugins
COPY ./start-teamcity-server.sh /start-teamcity-server.sh
COPY ./health-check ./opt/teamcity/webapps/health

# Teamcity server port 
EXPOSE 8111

CMD ["/start-teamcity-server.sh"]