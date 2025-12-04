#!/bin/bash

echo "=================================================="
echo "  Logstash NetFlow Configuration"
echo "=================================================="
echo ""

echo "1. NetFlow Pipeline Config:"
echo "----------------------------------------"
docker exec clab-ospf-network-logstash cat /usr/share/logstash/pipeline/netflow.conf

echo ""
echo "2. Logstash Main Config:"
echo "----------------------------------------"
docker exec clab-ospf-network-logstash cat /usr/share/logstash/config/logstash.yml | grep -v "^#" | grep -v "^$"

echo ""
echo "3. Check Codec Version Support:"
echo "----------------------------------------"
docker exec clab-ospf-network-logstash sh -c "ls -la /usr/share/logstash/vendor/bundle/jruby/*/gems/logstash-codec-netflow-*"

echo ""
echo "=================================================="
