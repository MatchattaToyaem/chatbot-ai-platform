FROM docker.elastic.co/beats/filebeat:8.13.0

USER root
COPY filebeat.yml /usr/share/filebeat/filebeat.yml
COPY filebeat-simple.yml /usr/share/filebeat/filebeat-simple.yml
COPY entrypoint.sh /usr/share/filebeat/entrypoint.sh
RUN chmod go-w /usr/share/filebeat/filebeat.yml /usr/share/filebeat/filebeat-simple.yml && \
    chmod +x /usr/share/filebeat/entrypoint.sh && \
    mkdir -p /usr/share/filebeat/data && \
    chmod 755 /usr/share/filebeat/data

ENTRYPOINT ["/usr/share/filebeat/entrypoint.sh"]
