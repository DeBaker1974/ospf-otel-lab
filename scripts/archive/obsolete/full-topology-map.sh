#!/bin/bash

echo "=== COMPLETE TOPOLOGY MAPPING ==="
echo ""

echo "1. All Nodes in Topology File:"
grep -E "^\s+[a-z0-9-]+:" ospf-network.clab.yml | grep -v "kind:" | sed 's/://g'

echo ""
echo "2. All Links:"
sed -n '/^  links:/,/^[a-z]/p' ospf-network.clab.yml | grep "endpoints"

echo ""
echo "3. SW2 Details:"
grep -B 3 -A 10 "sw2:" ospf-network.clab.yml

echo ""
echo "4. SW (Bottom Switch) Details:"
grep -B 3 -A 10 '^\s\+sw:' ospf-network.clab.yml

echo ""
echo "5. Linux-bottom Connection:"
sed -n '/^  links:/,/^[a-z]/p' ospf-network.clab.yml | grep "linux-bottom"

echo ""
echo "6. Linux-top Connection:"
sed -n '/^  links:/,/^[a-z]/p' ospf-network.clab.yml | grep "linux-top"

echo ""
echo "7. CSR25 Connections:"
sed -n '/^  links:/,/^[a-z]/p' ospf-network.clab.yml | grep "csr25"

echo ""
echo "8. CSR23 Connections:"
sed -n '/^  links:/,/^[a-z]/p' ospf-network.clab.yml | grep "csr23"

echo ""
echo "9. Running Containers:"
docker ps --filter "name=clab-ospf-network" --format "{{.Names}}" | sort

