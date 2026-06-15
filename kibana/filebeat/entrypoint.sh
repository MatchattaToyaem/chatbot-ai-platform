#!/bin/bash
if [ "$FILEBEAT_TYPE" = "simple" ]; then
  exec filebeat -e -c /usr/share/filebeat/filebeat-simple.yml
else
  exec filebeat -e -c /usr/share/filebeat/filebeat.yml
fi
