#!/bin/bash

echo "========================================="
echo "OSPF Network Lab - Topology v12.0"
echo "========================================="
echo ""
echo "Network Design:"
echo ""
cat << 'TOPOLOGY'
                    ┌─────────────────────────────────────────┐
                    │         OSPF Area 0                     │
                    │         All Routers: 10.255.0.x/32      │
                    └─────────────────────────────────────────┘

                                CSR28 (10.255.0.28)
                                  (Core/Edge)
                                 192.168.20.1/24
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
              10.0.1.0/31       10.0.2.0/31            │
                    │                 │                sw2 (L2 Bridge)
                    │                 │                 │
                    │                 │              node1
    ┌───────────────┴─────────────┐   ┌────┴──────────────┐   (192.168.20.100/24)
    │                        │   │                   │
CSR24 (10.255.0.24)      CSR23 (10.255.0.23)
(Distribution Left)      (Distribution Right)
    │                        │
    ├──10.0.9.0/31           ├──10.0.7.0/31
    │                        │
    ├──10.0.3.0/31────────────
    │                        │
    ├──10.0.4.0/31           ├──10.0.5.0/31
    │                        │
    ├──10.0.6.0/31           ├──10.0.11.0/31
    │                        │
    │                        │
    │                        │
    │       CSR29            │           CSR27
    │    (10.255.0.29)       │        (10.255.0.27)
    │     (Edge Left)        │        (Edge Right)
    │         │              │             │
    └─────10.0.9.0/31        │       10.0.11.0/31
            │                │             │
        10.0.10.0/31         │        10.0.12.0/31
            │                │             │
            │                │             │
    ┌───────┴──────────────────┴─────────┴─────────┐
    │                                               │
    │                 VRRP Pair                     │
    │          (192.168.10.0/24 Network)            │
    │                                               │
    │    CSR26 (10.255.0.26)    10.0.8.0/31    CSR25 (10.255.0.25)
    │    192.168.10.3/24  ◄─────────────────►  192.168.10.2/24
    │    VRRP Priority: 90                     VRRP Priority: 110
    │    (Standby)                             (Active/Master)
    │         │                                      │
    │         │                                      │
    │    ┌────┴──────────────────┬──────────────────┘
    │    │                            │
    │    └────► sw (L2 Bridge) ◄──────┘
    │                │
    │                ├──── win-bottom (192.168.10.10/24)
    │                │
    │                └──── linux-bottom (192.168.10.20/24)
    │
    └───────────────────────────────────────────────

VRRP Virtual IP: 192.168.10.1 (shared gateway)
Default route for end devices → 192.168.10.1
TOPOLOGY

echo ""
echo "========================================="
echo "Telemetry Stack Architecture"
echo "========================================="
echo ""
cat << 'TELEMETRY'
┌─────────────────────────────────────────────────────────────────┐
│                        Data Sources                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │  CSR23   │  │  CSR24   │  │  CSR25   │  │  CSR26   │  ...  │
│  ├──────────┤  ├──────────┤  ├──────────┤  ├──────────┤       │
│  │ SNMP:161 │  │ SNMP:161 │  │ SNMP:161 │  │ SNMP:161 │       │
│  │ Syslog   │  │ Syslog   │  │ Syslog   │  │ Syslog   │       │
│  │ LLDP     │  │ LLDP     │  │ LLDP     │  │ LLDP     │       │
│  │ NetFlow  │  │ NetFlow  │  │ NetFlow  │  │ NetFlow  │       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
│       │             │             │             │               │
└───────┼─────────────┼─────────────┼─────────────┼───────────────┘
        │             │             │             │
        ├─────SNMP────┼─────────────┼─────────────┤
        │             │             │             │
        ├─────Syslog──┼─────────────┼─────────────┤
        │             │             │             │
        │             └─────NetFlow─────────┐     │
        │                                   │     │
        ▼                                   ▼     ▼
┌─────────────────────┐           ┌──────────────────────┐
│  OTEL Collector     │           │     Logstash         │
│  (172.20.20.12)     │           │  (172.20.20.10)      │
├─────────────────────┤           ├──────────────────────┤
│ • SNMP Receiver     │           │ • NetFlow v5/v9      │
│   - 7 routers       │           │   Input (UDP 2055)   │
│   - 30+ metrics     │           │ • Codec: NetFlow     │
│   - 10s interval    │           │ • Filter: Enrich     │
│                     │           │ • Output: ES         │
│ • Syslog Receiver   │           │                      │
│   - UDP 5140        │           │ Pipeline Status:     │
│   - Structured logs │           │ [Loading/Running]    │
│                     │           │                      │
│ • Processors        │           │ Data Tagged:         │
│   - Resource        │           │ • Internal networks  │
│   - Attributes      │           │ • Flow direction     │
│   - Batch           │           │ • Protocol info      │
│                     │           │                      │
│ • Exporters         │           └──────────┬───────────┘
│   - Elasticsearch   │                      │
│   - OTLP HTTP       │                      │
│   - Debug (logs)    │                      │
└──────────┬──────────┘                      │
           │                                 │
           │                                 │
           ▼                                 ▼
┌────────────────────────────────────────────────────────────────┐
│              Elasticsearch Serverless                          │
│              (network-demo-f289e8)                             │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Data Streams:                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ metrics-snmp.metrics-prod                              │   │
│  │ • Interface stats (ifInOctets, ifOutOctets)            │   │
│  │ • System metrics (CPU, memory, uptime)                 │   │
│  │ • Protocol counters (IP, TCP, UDP, ICMP)               │   │
│  │ • ARP table entries                                    │   │
│  │ Collection: ~900K+ documents                           │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ logs-frr.log-default                                   │   │
│  │ • FRR routing daemon logs                              │   │
│  │ • OSPF neighbor changes                                │   │
│  │ • Interface state changes                              │   │
│  │ • System events                                        │   │
│  │ Collection: Real-time                                  │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ lldp-topology                                          │   │
│  │ • Neighbor discovery                                   │   │
│  │ • Interface mappings                                   │   │
│  │ • Chassis/Port IDs                                     │   │
│  │ • System capabilities                                  │   │
│  │ Collection: 10s interval, ~160K+ documents             │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ logs-netflow-default                                   │   │
│  │ • Flow records (src/dst IP, ports)                     │   │
│  │ • Packet/byte counters                                 │   │
│  │ • Protocol identification                              │   │
│  │ • Flow timestamps                                      │   │
│  │ Collection: Real-time (when traffic flows)             │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
│  Total Documents: 1,000,000+ and growing                       │
│  Retention: Managed by Elasticsearch ILM                       │
│  Query Performance: Optimized for time-series                  │
│                                                                │
└────────────────────────────────────────────────────────────────┘

TELEMETRY

echo ""
echo "========================================="
echo "LLDP Configuration"
echo "========================================="
echo ""
echo "LLDP Status: rx-and-tx (transmit and receive)"
echo "TX Interval: 10 seconds"
echo "TX Hold: 4 (40 seconds TTL)"
echo ""
echo "LLDP Collection Methods:"
echo "  1. Via SNMP (OTEL Collector)"
echo "     • Interval: 30 seconds"
echo "     • OID: LLDP-MIB"
echo "     • Pros: Integrated with other metrics"
echo ""
echo "  2. Via Direct Collection (systemd service)"
echo "     • Interval: 10 seconds"
echo "     • Command: lldpcli show neighbors"
echo "     • Pros: More detailed, faster updates"
echo "     • Service: lldp-topology-collector.service"
echo ""

echo ""
echo "========================================="
echo "NetFlow Configuration"
echo "========================================="
echo ""
echo "NetFlow Exporters (softflowd):"
echo "  • Version: NetFlow v5 (compatible with v9)"
echo "  • Collector: Logstash (172.20.20.10:2055)"
echo "  • Monitored Interfaces: All router interfaces"
echo "  • Timeout: 60s (flow expiration)"
echo "  • Max Flows: 65535 per router"
echo ""
echo "Flow Information Captured:"
echo "  • Source/Destination IP addresses"
echo "  • Source/Destination ports"
echo "  • Protocol (TCP/UDP/ICMP/etc)"
echo "  • Packet count"
echo "  • Byte count"
echo "  • Flow start/end timestamps"
echo "  • Input/Output interface"
echo ""
echo "Setup NetFlow:"
echo "  ./scripts/setup-netflow.sh"
echo ""
echo "Generate Test Traffic:"
echo "  ./scripts/generate-traffic.sh"
echo ""

echo ""
echo "========================================="
echo "Key Metrics & Collection Intervals"
echo "========================================="
echo ""
echo "SNMP Metrics (via OTEL Collector):"
echo "  System & Interfaces:     10s"
echo "    • ifInOctets, ifOutOctets, ifOperStatus"
echo "    • sysUpTime, hrSystemUptime"
echo "    • hrProcessorLoad, hrStorageUsed"
echo ""
echo "  IP Statistics:           15s"
echo "    • ipInReceives, ipOutRequests"
echo "    • ipInDelivers, ipForwDatagrams"
echo ""
echo "  TCP/UDP Statistics:      15s"
echo "    • tcpActiveOpens, tcpInSegs, tcpOutSegs"
echo "    • udpInDatagrams, udpOutDatagrams"
echo ""
echo "  ICMP Statistics:         15s"
echo "    • icmpInMsgs, icmpOutMsgs"
echo "    • icmpInErrors, icmpOutErrors"
echo ""
echo "  ARP Table:               30s"
echo "    • ipNetToMediaPhysAddress"
echo "    • ipNetToMediaNetAddress"
echo ""
echo "Syslog Events:             Real-time"
echo "  • FRR routing events"
echo "  • Interface state changes"
echo "  • System notifications"
echo ""
echo "LLDP Topology:             10s"
echo "  • Neighbor discovery"
echo "  • Interface connections"
echo "  • System information"
echo ""
echo "NetFlow:                   Real-time"
echo "  • Active flow monitoring"
echo "  • Traffic patterns"
echo "  • Protocol distribution"
echo ""

echo ""
echo "========================================="
echo "Quick Commands"
echo "========================================="
echo ""
echo "Status & Monitoring:"
echo "  ./status.sh                           - Full system status"
echo "  ./connect.sh                          - Interactive menu"
echo ""
echo "OSPF Verification:"
echo "  docker exec clab-ospf-network-csr28 vtysh -c 'show ip ospf neighbor'"
echo "  docker exec clab-ospf-network-csr28 vtysh -c 'show ip route ospf'"
echo ""
echo "VRRP Status:"
echo "  docker exec clab-ospf-network-csr25 vtysh -c 'show vrrp'"
echo "  docker exec clab-ospf-network-csr26 vtysh -c 'show vrrp'"
echo ""
echo "LLDP Neighbors:"
echo "  ./scripts/show-lldp-neighbors.sh"
echo ""
echo "NetFlow Status:"
echo "  ./scripts/check-netflow-status.sh     - Check exporters"
echo "  docker logs -f clab-ospf-network-logstash  - View collector logs"
echo ""
echo "Traffic Testing:"
echo "  docker exec clab-ospf-network-win-bottom ping -c 10 192.168.20.100"
echo "  docker exec clab-ospf-network-node1 ping -c 10 192.168.10.10"
echo ""
echo "Data Verification:"
echo "  ./scripts/verify-all-data.sh          - Check all data streams"
echo "  ./scripts/list-all-metrics.sh         - List collected metrics"
echo ""
echo "Telemetry Logs:"
echo "  docker logs -f clab-ospf-network-otel-collector"
echo "  docker logs -f clab-ospf-network-logstash"
echo ""

echo ""
echo "========================================="
echo "Network Summary"
echo "========================================="
echo ""
echo "Total Routers: 7"
echo "  • Core/Edge:     CSR28"
echo "  • Distribution:  CSR23, CSR24"
echo "  • Access/Edge:   CSR25, CSR26 (VRRP), CSR27, CSR29"
echo ""
echo "End Devices: 3"
echo "  • win-bottom:    192.168.10.10/24"
echo "  • linux-bottom:  192.168.10.20/24"
echo "  • node1:         192.168.20.100/24"
echo ""
echo "Telemetry: 2"
echo "  • OTEL Collector:  172.20.20.12"
echo "  • Logstash:        172.20.20.10"
echo ""
echo "Protocols:"
echo "  • Routing:       OSPF (Area 0)"
echo "  • Redundancy:    VRRP (192.168.10.1)"
echo "  • Discovery:     LLDP"
echo "  • Management:    SNMPv2c"
echo "  • Logging:       Syslog (UDP 5140)"
echo "  • Flow Export:   NetFlow v5/v9 (UDP 2055)"
echo ""
echo "Data Streams:"
echo "  • SNMP Metrics:   metrics-snmp.metrics-prod"
echo "  • FRR Logs:       logs-frr.log-default"
echo "  • LLDP Topology:  lldp-topology"
echo "  • NetFlow:        logs-netflow-default"
echo ""
echo "Total Data: 1,000,000+ documents in Elasticsearch"
echo ""
echo "========================================="
