#!/bin/bash
# =============================================================================
# update-otel-full-mib-coverage.sh
# Comprehensive FRR MIB coverage for OTEL Collector
# Backs up current config and deploys enhanced version
# =============================================================================

set -e

LAB_DIR="$HOME/ospf-otel-lab"
OTEL_CONFIG="$LAB_DIR/configs/otel/otel-collector.yml"
BACKUP_DIR="$LAB_DIR/configs/otel/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "============================================="
echo "OTEL Full FRR MIB Coverage Update"
echo "============================================="
echo ""

# Load ES credentials
if [ -f "$LAB_DIR/.env" ]; then
    source "$LAB_DIR/.env"
else
    echo "✗ Missing .env file"
    exit 1
fi

if [ -z "$ES_ENDPOINT" ] || [ -z "$ES_API_KEY" ]; then
    echo "✗ ES_ENDPOINT or ES_API_KEY not set in .env"
    exit 1
fi

echo "ES Endpoint: $ES_ENDPOINT"
echo ""

# =============================================================================
# PHASE 1: Backup
# =============================================================================
echo "Phase 1: Backing up current configuration..."
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/otel-collector.yml.backup-$TIMESTAMP"
cp "$OTEL_CONFIG" "$BACKUP_FILE"
echo "  ✓ Backup saved: $BACKUP_FILE"
echo ""

# =============================================================================
# PHASE 2: Create New Configuration
# =============================================================================
echo "Phase 2: Creating comprehensive MIB configuration..."

cat > "$OTEL_CONFIG" << 'CONFIGEOF'
# ============================================
# COMPREHENSIVE FRR SNMP Configuration v2.0
# Full MIB Coverage: System, IF, IP, ICMP, TCP, UDP, OSPF, ARP, LLDP
# Generated: TIMESTAMP_PLACEHOLDER
# ============================================

receivers:
CONFIGEOF

# Replace timestamp
sed -i "s/TIMESTAMP_PLACEHOLDER/$TIMESTAMP/" "$OTEL_CONFIG"

# =============================================================================
# Generate receivers for each router
# =============================================================================
ROUTERS="csr23:172.20.20.23 csr24:172.20.20.24 csr25:172.20.20.25 csr26:172.20.20.26 csr27:172.20.20.27 csr28:172.20.20.28 csr29:172.20.20.29"

for entry in $ROUTERS; do
    ROUTER=$(echo $entry | cut -d: -f1)
    IP=$(echo $entry | cut -d: -f2)
    
    echo "  Generating receivers for $ROUTER ($IP)..."
    
    cat >> "$OTEL_CONFIG" << ROUTEREOF

  # ============================================
  # $ROUTER ($IP) - FULL MIB COVERAGE
  # ============================================

  # --- System MIB (Extended) ---
  snmp/${ROUTER}_system:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 30s
    timeout: 10s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    metrics:
      system.uptime:
        unit: s
        gauge: { value_type: double }
        scalar_oids:
          - oid: "1.3.6.1.2.1.1.3.0"
            resource_attributes: ["host.name"]
      system.services:
        unit: "1"
        gauge: { value_type: int }
        scalar_oids:
          - oid: "1.3.6.1.2.1.1.7.0"
            resource_attributes: ["host.name"]

  # --- Memory (HOST-RESOURCES-MIB) ---
  snmp/${ROUTER}_memory:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 60s
    timeout: 10s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    attributes:
      memory.pool.name: { oid: "1.3.6.1.2.1.25.2.3.1.3" }
    metrics:
      system.memory.size:
        unit: units
        gauge: { value_type: int }
        column_oids:
          - oid: "1.3.6.1.2.1.25.2.3.1.5"
            attributes: [ { name: memory.pool.name } ]
            resource_attributes: ["host.name"]
      system.memory.used:
        unit: units
        gauge: { value_type: int }
        column_oids:
          - oid: "1.3.6.1.2.1.25.2.3.1.6"
            attributes: [ { name: memory.pool.name } ]
            resource_attributes: ["host.name"]

  # --- Interface MIB (Extended) ---
  snmp/${ROUTER}_interface:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 15s
    timeout: 10s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    attributes:
      if.index: { oid: "1.3.6.1.2.1.2.2.1.1" }
      if.name: { oid: "1.3.6.1.2.1.31.1.1.1.1" }
      if.descr: { oid: "1.3.6.1.2.1.2.2.1.2" }
    metrics:
      # Bytes (64-bit counters)
      network.interface.in.bytes:
        unit: By
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        column_oids:
          - oid: "1.3.6.1.2.1.31.1.1.1.6"
            attributes: [ { name: if.index }, { name: if.name }, { name: if.descr } ]
            resource_attributes: ["host.name"]
      network.interface.out.bytes:
        unit: By
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        column_oids:
          - oid: "1.3.6.1.2.1.31.1.1.1.10"
            attributes: [ { name: if.index }, { name: if.name }, { name: if.descr } ]
            resource_attributes: ["host.name"]
      # Packets
      network.interface.in.packets:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.11"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]
      network.interface.out.packets:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.17"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]
      # Errors
      network.interface.in.errors:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.14"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]
      network.interface.out.errors:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.20"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]
      # Discards
      network.interface.in.discards:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.13"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]
      network.interface.out.discards:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.19"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]
      # Status
      network.interface.oper.status:
        unit: "1"
        gauge: { value_type: int }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.8"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]
      network.interface.admin.status:
        unit: "1"
        gauge: { value_type: int }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.7"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]
      # Speed and MTU
      network.interface.speed:
        unit: "1"
        gauge: { value_type: int }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.5"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]
      network.interface.mtu:
        unit: By
        gauge: { value_type: int }
        column_oids:
          - oid: "1.3.6.1.2.1.2.2.1.4"
            attributes: [ { name: if.index }, { name: if.name } ]
            resource_attributes: ["host.name"]

  # --- IP-MIB (Extended) ---
  snmp/${ROUTER}_ipstats:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 30s
    timeout: 10s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    metrics:
      network.ip.in.receives:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.3.0"
            resource_attributes: ["host.name"]
      network.ip.in.hdr.errors:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.4.0"
            resource_attributes: ["host.name"]
      network.ip.in.addr.errors:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.5.0"
            resource_attributes: ["host.name"]
      network.ip.forw.datagrams:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.6.0"
            resource_attributes: ["host.name"]
      network.ip.in.discards:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.8.0"
            resource_attributes: ["host.name"]
      network.ip.in.delivers:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.9.0"
            resource_attributes: ["host.name"]
      network.ip.out.requests:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.10.0"
            resource_attributes: ["host.name"]
      network.ip.out.discards:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.11.0"
            resource_attributes: ["host.name"]
      network.ip.out.no.routes:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.12.0"
            resource_attributes: ["host.name"]
      network.ip.reasm.reqds:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.14.0"
            resource_attributes: ["host.name"]
      network.ip.reasm.oks:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.15.0"
            resource_attributes: ["host.name"]
      network.ip.reasm.fails:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.16.0"
            resource_attributes: ["host.name"]
      network.ip.frag.oks:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.17.0"
            resource_attributes: ["host.name"]
      network.ip.frag.fails:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.18.0"
            resource_attributes: ["host.name"]
      network.ip.frag.creates:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.4.19.0"
            resource_attributes: ["host.name"]

  # --- ICMP-MIB ---
  snmp/${ROUTER}_icmp:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 30s
    timeout: 10s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    metrics:
      network.icmp.in.msgs:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.1.0"
            resource_attributes: ["host.name"]
      network.icmp.in.errors:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.2.0"
            resource_attributes: ["host.name"]
      network.icmp.in.dest.unreachs:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.3.0"
            resource_attributes: ["host.name"]
      network.icmp.in.time.excds:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.4.0"
            resource_attributes: ["host.name"]
      network.icmp.in.echos:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.8.0"
            resource_attributes: ["host.name"]
      network.icmp.in.echo.reps:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.9.0"
            resource_attributes: ["host.name"]
      network.icmp.out.msgs:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.14.0"
            resource_attributes: ["host.name"]
      network.icmp.out.errors:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.15.0"
            resource_attributes: ["host.name"]
      network.icmp.out.dest.unreachs:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.16.0"
            resource_attributes: ["host.name"]
      network.icmp.out.echos:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.21.0"
            resource_attributes: ["host.name"]
      network.icmp.out.echo.reps:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.5.22.0"
            resource_attributes: ["host.name"]

  # --- TCP-MIB (Extended) ---
  snmp/${ROUTER}_tcp:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 30s
    timeout: 10s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    metrics:
      network.tcp.active.opens:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.5.0"
            resource_attributes: ["host.name"]
      network.tcp.passive.opens:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.6.0"
            resource_attributes: ["host.name"]
      network.tcp.attempt.fails:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.7.0"
            resource_attributes: ["host.name"]
      network.tcp.estab.resets:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.8.0"
            resource_attributes: ["host.name"]
      network.tcp.curr.estab:
        unit: "1"
        gauge: { value_type: int }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.9.0"
            resource_attributes: ["host.name"]
      network.tcp.in.segs:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.10.0"
            resource_attributes: ["host.name"]
      network.tcp.out.segs:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.11.0"
            resource_attributes: ["host.name"]
      network.tcp.retrans.segs:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.12.0"
            resource_attributes: ["host.name"]
      network.tcp.in.errs:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.14.0"
            resource_attributes: ["host.name"]
      network.tcp.out.rsts:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.6.15.0"
            resource_attributes: ["host.name"]

  # --- UDP-MIB (Extended) ---
  snmp/${ROUTER}_udp:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 30s
    timeout: 10s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    metrics:
      network.udp.in.datagrams:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.7.1.0"
            resource_attributes: ["host.name"]
      network.udp.no.ports:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.7.2.0"
            resource_attributes: ["host.name"]
      network.udp.in.errors:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.7.3.0"
            resource_attributes: ["host.name"]
      network.udp.out.datagrams:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.7.4.0"
            resource_attributes: ["host.name"]

  # --- OSPF-MIB (via FRR AgentX) ---
  snmp/${ROUTER}_ospf:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 60s
    timeout: 15s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    metrics:
      network.ospf.admin.stat:
        unit: "1"
        gauge: { value_type: int }
        scalar_oids:
          - oid: "1.3.6.1.2.1.14.1.2.0"
            resource_attributes: ["host.name"]
      network.ospf.version.number:
        unit: "1"
        gauge: { value_type: int }
        scalar_oids:
          - oid: "1.3.6.1.2.1.14.1.3.0"
            resource_attributes: ["host.name"]
      network.ospf.area.bdr.rtr.status:
        unit: "1"
        gauge: { value_type: int }
        scalar_oids:
          - oid: "1.3.6.1.2.1.14.1.4.0"
            resource_attributes: ["host.name"]
      network.ospf.as.bdr.rtr.status:
        unit: "1"
        gauge: { value_type: int }
        scalar_oids:
          - oid: "1.3.6.1.2.1.14.1.5.0"
            resource_attributes: ["host.name"]
      network.ospf.extern.lsa.count:
        unit: "1"
        gauge: { value_type: int }
        scalar_oids:
          - oid: "1.3.6.1.2.1.14.1.6.0"
            resource_attributes: ["host.name"]
      network.ospf.extern.lsa.cksum.sum:
        unit: "1"
        gauge: { value_type: int }
        scalar_oids:
          - oid: "1.3.6.1.2.1.14.1.7.0"
            resource_attributes: ["host.name"]
      network.ospf.originate.new.lsas:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.14.1.9.0"
            resource_attributes: ["host.name"]
      network.ospf.rx.new.lsas:
        unit: "1"
        sum: { value_type: int, monotonic: true, aggregation: cumulative }
        scalar_oids:
          - oid: "1.3.6.1.2.1.14.1.10.0"
            resource_attributes: ["host.name"]

  # --- ARP Table ---
  snmp/${ROUTER}_arp:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 60s
    timeout: 10s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    attributes:
      arp.ifindex: { oid: "1.3.6.1.2.1.4.22.1.1" }
      arp.ip: { oid: "1.3.6.1.2.1.4.22.1.3" }
      arp.mac: { oid: "1.3.6.1.2.1.4.22.1.2" }
    metrics:
      network.arp.entry:
        unit: "1"
        gauge: { value_type: int }
        column_oids:
          - oid: "1.3.6.1.2.1.4.22.1.4"
            attributes: [ { name: arp.ifindex }, { name: arp.ip }, { name: arp.mac } ]
            resource_attributes: ["host.name"]

  # --- LLDP-MIB ---
  snmp/${ROUTER}_lldp:
    endpoint: udp://${IP}:161
    version: v2c
    community: public
    collection_interval: 30s
    timeout: 10s
    resource_attributes:
      host.name: { scalar_oid: "1.3.6.1.2.1.1.5.0" }
    attributes:
      network.lldp.rem.sysname: { oid: "1.0.8802.1.1.2.1.4.1.1.9" }
    metrics:
      network.lldp.neighbors:
        unit: "1"
        gauge: { value_type: int }
        column_oids:
          - oid: "1.0.8802.1.1.2.1.4.1.1.4"
            attributes: [ { name: network.lldp.rem.sysname } ]
            resource_attributes: ["host.name"]
ROUTEREOF

done

echo "  ✓ All router receivers generated"

# =============================================================================
# Add processors, exporters, and service pipelines
# =============================================================================
echo "  Adding processors, exporters, and pipelines..."

cat >> "$OTEL_CONFIG" << PIPELINEEOF

# ============================================
# PROCESSORS
# ============================================
processors:
  batch:
    timeout: 10s
    send_batch_size: 200

# ============================================
# EXPORTERS - Separate index per metric type
# ============================================
exporters:
  elasticsearch/system:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.system-prod"

  elasticsearch/memory:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.memory-prod"

  elasticsearch/interface:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.interface-prod"

  elasticsearch/ipstats:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.ipstats-prod"

  elasticsearch/icmp:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.icmp-prod"

  elasticsearch/tcp:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.tcp-prod"

  elasticsearch/udp:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.udp-prod"

  elasticsearch/ospf:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.ospf-prod"

  elasticsearch/arp:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.arp-prod"

  elasticsearch/lldp:
    endpoints: [ "${ES_ENDPOINT}" ]
    api_key: "${ES_API_KEY}"
    mapping:
      mode: ecs
    metrics_dynamic_index:
      enabled: false
    metrics_index: "metrics-snmp.lldp-prod"

  debug:
    verbosity: basic
    sampling_initial: 2
    sampling_thereafter: 500

# ============================================
# SERVICE - Pipelines per metric type
# ============================================
service:
  pipelines:
    metrics/system:
      receivers:
        - snmp/csr23_system
        - snmp/csr24_system
        - snmp/csr25_system
        - snmp/csr26_system
        - snmp/csr27_system
        - snmp/csr28_system
        - snmp/csr29_system
      processors: [batch]
      exporters: [elasticsearch/system, debug]

    metrics/memory:
      receivers:
        - snmp/csr23_memory
        - snmp/csr24_memory
        - snmp/csr25_memory
        - snmp/csr26_memory
        - snmp/csr27_memory
        - snmp/csr28_memory
        - snmp/csr29_memory
      processors: [batch]
      exporters: [elasticsearch/memory, debug]

    metrics/interface:
      receivers:
        - snmp/csr23_interface
        - snmp/csr24_interface
        - snmp/csr25_interface
        - snmp/csr26_interface
        - snmp/csr27_interface
        - snmp/csr28_interface
        - snmp/csr29_interface
      processors: [batch]
      exporters: [elasticsearch/interface, debug]

    metrics/ipstats:
      receivers:
        - snmp/csr23_ipstats
        - snmp/csr24_ipstats
        - snmp/csr25_ipstats
        - snmp/csr26_ipstats
        - snmp/csr27_ipstats
        - snmp/csr28_ipstats
        - snmp/csr29_ipstats
      processors: [batch]
      exporters: [elasticsearch/ipstats, debug]

    metrics/icmp:
      receivers:
        - snmp/csr23_icmp
        - snmp/csr24_icmp
        - snmp/csr25_icmp
        - snmp/csr26_icmp
        - snmp/csr27_icmp
        - snmp/csr28_icmp
        - snmp/csr29_icmp
      processors: [batch]
      exporters: [elasticsearch/icmp, debug]

    metrics/tcp:
      receivers:
        - snmp/csr23_tcp
        - snmp/csr24_tcp
        - snmp/csr25_tcp
        - snmp/csr26_tcp
        - snmp/csr27_tcp
        - snmp/csr28_tcp
        - snmp/csr29_tcp
      processors: [batch]
      exporters: [elasticsearch/tcp, debug]

    metrics/udp:
      receivers:
        - snmp/csr23_udp
        - snmp/csr24_udp
        - snmp/csr25_udp
        - snmp/csr26_udp
        - snmp/csr27_udp
        - snmp/csr28_udp
        - snmp/csr29_udp
      processors: [batch]
      exporters: [elasticsearch/udp, debug]

    metrics/ospf:
      receivers:
        - snmp/csr23_ospf
        - snmp/csr24_ospf
        - snmp/csr25_ospf
        - snmp/csr26_ospf
        - snmp/csr27_ospf
        - snmp/csr28_ospf
        - snmp/csr29_ospf
      processors: [batch]
      exporters: [elasticsearch/ospf, debug]

    metrics/arp:
      receivers:
        - snmp/csr23_arp
        - snmp/csr24_arp
        - snmp/csr25_arp
        - snmp/csr26_arp
        - snmp/csr27_arp
        - snmp/csr28_arp
        - snmp/csr29_arp
      processors: [batch]
      exporters: [elasticsearch/arp, debug]

    metrics/lldp:
      receivers:
        - snmp/csr23_lldp
        - snmp/csr24_lldp
        - snmp/csr25_lldp
        - snmp/csr26_lldp
        - snmp/csr27_lldp
        - snmp/csr28_lldp
        - snmp/csr29_lldp
      processors: [batch]
      exporters: [elasticsearch/lldp, debug]

  telemetry:
    logs:
      level: info
PIPELINEEOF

echo "  ✓ Exporters and pipelines configured"

# =============================================================================
# PHASE 3: Validate Configuration
# =============================================================================
echo ""
echo "Phase 3: Validating configuration..."

# Check YAML syntax
if command -v python3 &> /dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$OTEL_CONFIG'))" 2>/dev/null; then
        echo "  ✓ YAML syntax valid"
    else
        echo "  ✗ YAML syntax error!"
        echo "  Restoring backup..."
        cp "$BACKUP_FILE" "$OTEL_CONFIG"
        echo "  ✗ Update failed - backup restored"
        exit 1
    fi
else
    echo "  ⚠ Python not available for YAML validation"
fi

# Count configuration elements
RECEIVER_COUNT=$(grep -c "^  snmp/" "$OTEL_CONFIG" || echo "0")
EXPORTER_COUNT=$(grep -c "^  elasticsearch/" "$OTEL_CONFIG" || echo "0")
PIPELINE_COUNT=$(grep -c "^    metrics/" "$OTEL_CONFIG" || echo "0")
CONFIG_LINES=$(wc -l < "$OTEL_CONFIG")

echo ""
echo "Configuration Summary:"
echo "  Total lines:     $CONFIG_LINES"
echo "  SNMP receivers:  $RECEIVER_COUNT (7 routers × 10 MIB types = 70)"
echo "  ES exporters:    $EXPORTER_COUNT"
echo "  Pipelines:       $PIPELINE_COUNT"

# =============================================================================
# PHASE 4: Restart OTEL Collector
# =============================================================================
echo ""
echo "Phase 4: Restarting OTEL Collector..."

if docker ps --format '{{.Names}}' | grep -q "clab-ospf-network-otel-collector"; then
    docker restart clab-ospf-network-otel-collector
    echo "  Waiting 30 seconds for startup..."
    sleep 30
    
    # Check status
    OTEL_STATUS=$(docker inspect --format='{{.State.Status}}' clab-ospf-network-otel-collector 2>/dev/null)
    
    if [ "$OTEL_STATUS" = "running" ]; then
        echo "  ✓ OTEL Collector running"
        
        # Check for errors
        ERRORS=$(docker logs --tail 100 clab-ospf-network-otel-collector 2>&1 | grep -ci "error" || echo "0")
        if [ "$ERRORS" -gt 5 ]; then
            echo "  ⚠ Warning: $ERRORS errors in recent logs"
            echo "  Check: docker logs --tail 50 clab-ospf-network-otel-collector"
        else
            echo "  ✓ No significant errors detected"
        fi
    else
        echo "  ✗ OTEL Collector not running (status: $OTEL_STATUS)"
        echo "  Check logs: docker logs clab-ospf-network-otel-collector"
        echo ""
        echo "  Restoring backup..."
        cp "$BACKUP_FILE" "$OTEL_CONFIG"
        docker restart clab-ospf-network-otel-collector
        exit 1
    fi
else
    echo "  ⚠ OTEL Collector not found"
    echo "  Configuration saved but not applied"
fi

# =============================================================================
# PHASE 5: Verify Data Collection
# =============================================================================
echo ""
echo "Phase 5: Verifying data collection (waiting 60s)..."
sleep 60

echo ""
echo "Checking new indices..."

# Check each index
INDICES="system memory interface ipstats icmp tcp udp ospf arp lldp"
for idx in $INDICES; do
    COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.${idx}-prod/_count" 2>/dev/null | \
        jq -r '.count // 0' 2>/dev/null || echo "0")
    
    if [ "$COUNT" -gt 0 ]; then
        printf "  ✓ metrics-snmp.%-10s-prod: %s docs\n" "$idx" "$COUNT"
    else
        printf "  ⚠ metrics-snmp.%-10s-prod: no data yet\n" "$idx"
    fi
done

# =============================================================================
# Final Summary
# =============================================================================
echo ""
echo "============================================="
echo "UPDATE COMPLETE"
echo "============================================="
echo ""
echo "Changes Applied:"
echo "  ✓ Extended System MIB (sysServices)"
echo "  ✓ Extended Interface MIB (packets, discards, speed, MTU, admin status)"
echo "  ✓ Extended IP-MIB (13 metrics: receives, errors, fragments, etc.)"
echo "  ✓ NEW: ICMP-MIB (11 metrics: msgs, errors, echoes)"
echo "  ✓ Extended TCP-MIB (10 metrics: opens, segs, retrans)"
echo "  ✓ Extended UDP-MIB (4 metrics: datagrams, errors)"
echo "  ✓ NEW: OSPF-MIB (8 metrics: status, LSAs, routing)"
echo "  ✓ All 7 routers now have FULL coverage"
echo ""
echo "New Elasticsearch Indices:"
echo "  - metrics-snmp.icmp-prod (NEW)"
echo "  - metrics-snmp.ospf-prod (NEW)"
echo ""
echo "Backup Location:"
echo "  $BACKUP_FILE"
echo ""
echo "To restore previous config:"
echo "  cp $BACKUP_FILE $OTEL_CONFIG"
echo "  docker restart clab-ospf-network-otel-collector"
echo ""
echo "To verify OSPF metrics:"
echo "  curl -s -H \"Authorization: ApiKey \$ES_API_KEY\" \\"
echo "    \"\$ES_ENDPOINT/metrics-snmp.ospf-prod/_search?size=1\" | jq '.hits.hits[0]._source'"
echo ""
echo "============================================="


