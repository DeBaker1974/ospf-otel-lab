# Building a Unified Network Observability Lab with Elastic and Containerlab

## Introduction

This lab provides a self-contained, reproducible **Containerlab** simulation of an **OSPF Area 0** network core. It features a mesh of 7 **FRR routers** and two Ubuntu hosts to simulate end-user traffic.

The primary focus is on comprehensive network observability, integrating three distinct data pipelines into a managed **Elastic Cloud** stack:

*   **SNMP Polling (Metrics):** Collected via an **OTEL Collector**.
*   **NetFlow (Traffic Analysis):** Exported from all routers and collected by an **Elastic Agent**.
*   **SNMP Traps (Events/Logs):** Sent from `csr23` and processed by **Logstash**.

**Implemented Use Cases:**
*   Simulate SNMP Traps for CSR23 (eth1 down/up) and recover the trap in Elastic.
*   Simulate CSR23 down/up and visualize the status in the "CSR23 - Interface Status" dashboard.
*   Utilize two Linux hosts to simulate additional workloads.

![Lab Topology](Images/lab-topology.jpg)

## Quick Start

> **⚠️ IMPORTANT:** This lab is designed for Elastic Cloud Hosted and has not been fully tested on Serverless and local deployment on laptops.

**1. Infrastructure Requirements**
Suggested instance sizes for deployment:
*   **GCP:** e2-standard-2 (2 vCPU, 1 core, 8 GB memory)
*   **AWS:** t3.large (2 vCPU, 8 GB memory)
*   **Azure:** Standard_B2ms (2 vCPU, 8 GB memory)

**2. Setup**
*   Download the repository:
    *   [DeBaker1974/Containerlab-OSPF: Containerlab OSPF Simulation with OTEL, NetFlow, and SNMP](https://github.com/DeBaker1974/Containerlab-OSPF)
*   Obtain the following credentials:
    *   Elasticsearch Endpoint and API Key
    *   Fleet URL and Token (from a policy with NetFlow integration)

**3. Installation**
Run the following commands in your terminal:

```bash
cd ospf-otel-lab/scripts
chmod +x *
./install-lab-prereqs.sh
# Log out and log back in here to apply Docker permissions
./configure-elasticsearch.sh
./complete-setup.sh
```

**4. Finalize**
*   Import the Kibana dashboard: "CSR23 - Interface Status".

---

## 1. High-Level Architecture

*   **Infrastructure:** Containerlab (Docker-based).
*   **Routing Protocol:** OSPF Area 0 (Single Area).
*   **Core Functions:** A mesh of 7 FRR routers simulating a Service Provider or Enterprise Core.
*   **Edge Functions:** Ubuntu hosts simulating end-user traffic (North/South).
*   **Observability Stack:** Elastic Stack (Cloud) receiving data via OTEL Collector, Logstash, and Elastic Agent.

## 2. Node Roles & Management IPs

All nodes reside on the clab management network: **172.20.20.0/24**.

| Node Name | Type | Mgmt IP | Role |
| :---: | :---: | :---: | :---: |
| **csr28** | FRR Router | .28 | **Top Hub / Core**. Gateway for Top Network. |
| **csr23** | FRR Router | .23 | **Core Router**. Metrics, **SNMP Trap Source**. |
| **csr24** | FRR Router | .24 | **Core Router**. Heavy mesh connectivity. |
| **csr25** | FRR Router | .25 | **Bottom Distribution**. Gateway for Bottom Network. |
| **csr26** | FRR Router | .26 | **Bottom Distribution**. Gateway for Bottom Network. |
| **csr27** | FRR Router | .27 | **Right Wing / Edge**. |
| **csr29** | FRR Router | .29 | **Left Wing / Edge**. |
| **linux-top** | Ubuntu Host | N/A | End User (Top). Data IP: 192.168.20.100. |
| **linux-bottom** | Ubuntu Host | N/A | End User (Bottom). Data IP: 192.168.10.20. |
| **elastic-agent** | Elastic Agent | .50 | **NetFlow Collector** (Port 2055). |
| **otel-col** | OTEL Contrib | Auto | **SNMP Poller**. Sends to Elastic Cloud. |
| **logstash** | Logstash | .31 | **SNMP Trap Receiver** (Port 1062). Sends to Elastic Cloud. |

## 3. Physical & Data Plane Topology

The network is structured as a vertical flow with a redundant core mesh.

### A. North (Top) Sector
*   **Components:** `linux-top` → `sw2` → `csr28`.
*   **Access Switch (sw2):**
    *   Connects `linux-top` (eth1).
    *   Connects `elastic-agent-sw2` (eth1).
    *   Uplink to `csr28` (eth3).
*   **Subnet:** 192.168.20.0/24 (Gateway: `csr28` IP .1).

### B. The Core Mesh (OSPF Area 0)
Routers connect via point-to-point **/31** links.

*   **CSR28 (Top Hub):** Down to `csr24`, `csr23`.
*   **CSR24 (Left Core):** Connects to `csr28` (Up), `csr23` (Cross), `csr29` (Left Edge), `csr26` (Down Left), `csr25` (Down Right).
*   **CSR23 (Right Core):** Connects to `csr28` (Up), `csr24` (Cross), `csr27` (Right Edge), `csr26` (Down Left), `csr25` (Down Right).
*   **CSR29 (Left Edge):** Connects to `csr24` & `csr26`.
*   **CSR27 (Right Edge):** Connects to `csr23` & `csr25`.

### C. South (Bottom) Sector
*   **Router Layer:** `csr25` and `csr26` act as redundant gateways.
*   **Access Switch (sw):**
    *   Uplink from `csr25` (eth5).
    *   Uplink from `csr26` (eth5).
    *   Connects `linux-bottom` (eth1).
*   **Subnet:** 192.168.10.0/24 (VRRP or ECMP style gateway on Routers .2 and .3).

## 4. Telemetry & Observability Architecture

Your setup uses three distinct pipelines flowing into **Elastic Cloud**.

### Pipeline 1: SNMP Polling (Metrics)
*   **Method:** Active Polling.
*   **Source:** `otel-collector` (Container).
*   **Targets:** All 7 Routers (172.20.20.23 - .29) on **UDP 161**.
*   **Data Types:**
    *   System Uptime, Memory.
    *   Interface Stats (see below).
    *   LLDP Neighbors.
    *   TCP/UDP/IP/ARP Stats.
*   **Destination:** Elastic Cloud (Indices: `metrics-snmp.*`).

| Metric | OID | Description | Type |
|--------|-----|-------------|------|
| `network.interface.in.bytes` | 1.3.6.1.2.1.31.1.1.1.6 | Bytes received (64-bit HC) | Counter |
| `network.interface.out.bytes` | 1.3.6.1.2.1.31.1.1.1.10 | Bytes transmitted (64-bit HC) | Counter |
| `network.interface.in.ucast.packets` | 1.3.6.1.2.1.2.2.1.11 | Unicast packets received | Counter |
| `network.interface.out.ucast.packets` | 1.3.6.1.2.1.2.2.1.17 | Unicast packets transmitted | Counter |
| `network.interface.in.errors` | 1.3.6.1.2.1.2.2.1.14 | Inbound errors | Counter |
| `network.interface.out.errors` | 1.3.6.1.2.1.2.2.1.20 | Outbound errors | Counter |
| `network.interface.in.discards` | 1.3.6.1.2.1.2.2.1.13 | Inbound discards | Counter |
| `network.interface.out.discards` | 1.3.6.1.2.1.2.2.1.19 | Outbound discards | Counter |
| `network.interface.admin.status` | 1.3.6.1.2.1.2.2.1.7 | Admin status (1=up, 2=down) | Gauge |
| `network.interface.status` | 1.3.6.1.2.1.2.2.1.8 | Oper status (1=up, 2=down) | Gauge |
| `network.interface.speed` | 1.3.6.1.2.1.31.1.1.1.15 | Interface speed (bps) | Gauge |

### Pipeline 2: NetFlow (Traffic Analysis)
*   **Method:** Push (Exporter).
*   **Source:** All Routers (via `softflowd` installed by `netflow-startup.sh`).
*   **Target:** `elastic-agent-sw2` (172.20.20.50) on **UDP 2055**.
*   **Data Types:** IP Flow data (5-tuple).
*   **Integration:** Fleet-managed Elastic Agent (Network Packet Capture integration).

### Pipeline 3: SNMP Traps (Events/Logs)
*   **Method:** Push (Trap/Notification).
*   **Source:** Explicitly configured on **csr23** only (per `snmpd.conf`).
*   **Configuration:** `trap2sink 172.20.20.31:1062`.
*   **Triggers:** Interface Up/Down events (monitored `eth1` through `eth5`).
*   **Target:** `logstash` (172.20.20.31) on **UDP 1062**.
*   **Processing:** Logstash maps OIDs to human-readable events (e.g., "Interface down on csr23").
*   **Destination:** Elastic Cloud (Data Stream: `logs-snmp.trap-prod`).

## 5. Routing Logic (OSPF)

Derived from `frr.conf`:
*   **Router ID:** Loopback IP `10.255.0.X` (e.g., 10.255.0.23).
*   **Area:** All interfaces are in **Area 0**.
*   **Network Type:** `point-to-point` is explicitly configured on links to reduce OSPF overhead (no DR/BDR election).

## 6. Directory Structure

Ensure your project directory (`~/ospf-otel-lab`) looks like this before starting:

```text
.
└── ospf-otel-lab
    ├── clab-ospf-network          # Deployment artifacts (auto-generated)
    ├── logs
    │   ├── journal
    │   └── apt
    ├── configs
    │   ├── elasticsearch
    │   ├── elastic-agent
    │   │   ├── state
    │   │   └── data
    │   ├── elastic-agent-state    # Bind mount for Agent container
    │   ├── kibana
    │   │   └── dashboards
    │   ├── logstash
    │   │   ├── config
    │   │   └── pipeline
    │   │       └── backups
    │   ├── otel
    │   │   ├── backups
    │   │   └── Archive
    │   └── routers
    │       ├── csr23
    │       │   ├── agentx
    │       │   └── archive
    │       ├── csr24
    │       │   └── agentx
    │       ├── csr25
    │       │   └── agentx
    │       ├── csr26
    │       │   └── agentx
    │       ├── csr27
    │       │   └── agentx
    │       ├── csr28
    │       │   └── agentx
    │       └── csr29
    │           └── agentx
    └── scripts
        ├── ./connect.sh
        └── ./complete-setup.sh
        └── ./configure-elasticsearch.sh
```

## 7. Detailed Deployment Steps

### Step 1: Install Dependencies
Run the prerequisite script to install Docker CE and Containerlab.

```bash
cd ~/ospf-otel-lab
chmod +x scripts/install-lab-prereqs.sh
./scripts/install-lab-prereqs.sh
```

> **⚠️ IMPORTANT:** You must **Log Out** and **Log Back In** after this step for Docker group permissions to take effect.

### Step 2: Configure Elastic Cloud Connection
Set up your connection to the Elastic Stack. This script validates your credentials and auto-configures the specific versions for the lab.

1.  Obtain your **Elasticsearch Endpoint** (HTTPS URL).
2.  Create a **Base64 Encoded API Key** in Kibana (Stack Management → Security → API Keys).
3.  Create a Fleet policy enabling **Netflow Capture**.
4.  Create policy and add the integration: https://www.elastic.co/docs/reference/fleet/agent-policy#create-a-policy
      Set:
       - UDP host to listen on : 0.0.0.0
       - UDP port to listen on : 2055
5.  Obtain the Fleet URL and the policy token.
   a. Get a fleet token: https://www.elastic.co/docs/reference/fleet/fleet-enrollment-tokens     

Run the configuration wizard:

```bash
chmod +x scripts/configure-elasticsearch.sh
./scripts/configure-elasticsearch.sh
```

**What this does:**
*   Tests connectivity to Elastic Cloud.
*   Detects if you are using Serverless or Traditional Elastic.
*   Generates a local `.env` file used by the deployment script.
*   Hardcodes specific configuration files with your credentials.

### Step 3: Deploy the Network
Run the master deployment script. This is a "Zero-Touch" deployment that builds the entire topology and configures telemetry.

```bash
chmod +x scripts/complete-setup.sh
./scripts/complete-setup.sh
```

**This process takes approximately 12-15 minutes.**
*   **Cleanup:** Removes old containers and network bridges.
*   **Deploy:** Launches 14 containers defined in `ospf-network.clab.yml`.
*   **Bootstrap:** Installs `snmpd`, `lldpd`, and `softflowd` inside the FRR routers.
*   **Configure:** Enables SNMP AgentX for LLDP integration.
*   **Converge:** Waits for OSPF adjacencies to form.
*   **Verify:** Checks data flow for SNMP, LLDP, and Traps.

## 8. Verification & Access

### Lab Status Summary
At the end of the deployment, the script provides a health summary:
*   **SNMP:** Should show 7/7 routers responding.
*   **LLDP:** Should show neighbor relationships detected via SNMP.
*   **Elasticsearch:** Should verify data ingestion counts (Metrics & Logs).

### Accessing Devices
*   **Routers (VTysh):**
    ```bash
    docker exec -it clab-ospf-network-csr28 vtysh
    ```
*   **Linux Clients:**
    ```bash
    docker exec -it clab-ospf-network-linux-top bash
    ```
*   **Logstash Logs:**
    ```bash
    docker logs -f clab-ospf-network-logstash
    ```

## 9. Telemetry Data Flow Summary

| Data Type | Source | Transport | Collector | Destination |
| :---- | :---: | :---: | :---: | :---: |
| **Metrics** | FRR Routers | UDP 161 (SNMP) | OTEL Collector | `metrics-snmp.*` |
| **Traps** | CSR23 | UDP 1062 (SNMP Trap) | Logstash | `logs-snmp.trap-*` |
| **NetFlow** | All Routers | UDP 2055 (NetFlow v5) | Elastic Agent | `logs-network_traffic.*` |
| **Topology** | FRR Routers | AgentX (LLDP) | OTEL Collector | `lldp-topology` |

## 10. Transform: net-lldp-edges

To create the `net-lldp-edges` Index Mapping and Transform:
*   Ensure the setup is complete before executing this transform.
*   Ensure LLDP data is flowing.
*   Ensure the `lldp-topology` index exists.

**Create mapping:**

```json
PUT net-lldp-edges
{
  "mappings": {
    "properties": {
      "src_router": { "type": "keyword" },
      "dst_router": { "type": "keyword" },
      "last_seen": { "type": "date" },
      "first_seen": { "type": "date" },
      "observation_count": { "type": "long" },
      "neighbor_count": { "type": "long" }
    }
  },
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 1,
    "refresh_interval": "30s"
  }
}
```

**Create the transform:**

```json
PUT _transform/lldp-topology-to-edges
{
  "source": {
    "index": ["metrics-lldp-prod"],
    "query": {
      "bool": {
        "must": [
          { "exists": { "field": "network.lldp.rem.sysname" } }
        ],
        "must_not": [
          { "term": { "network.lldp.rem.sysname": "" } }
        ]
      }
    }
  },
  "dest": { "index": "net-lldp-edges" },
  "frequency": "1m",
  "sync": {
    "time": { "field": "@timestamp", "delay": "60s" }
  },
  "pivot": {
    "group_by": {
      "src_router": { "terms": { "field": "host.name" } },
      "dst_router": { "terms": { "field": "network.lldp.rem.sysname" } }
    },
    "aggregations": {
      "last_seen": { "max": { "field": "@timestamp" } },
      "first_seen": { "min": { "field": "@timestamp" } },
      "observation_count": { "value_count": { "field": "@timestamp" } },
      "neighbor_count": { "max": { "field": "network.lldp.neighbors" } }
    }
  },
  "description": "LLDP network topology - router-to-router connections (simplified)",
  "settings": { "max_page_search_size": 500 }
}
```

## 11. Create Alert in Kibana

1.  Navigate to: **Stack management > Rules > Create rules**
2.  Search: **Elasticsearch query**
3.  Select: **ES|QL**

**Query:**
```esql
FROM logs-snmp.trap-prod
| WHERE snmp.trap_oid == "1.3.6.1.6.3.1.1.5.3"
| KEEP @timestamp, host.name, interface.name, snmp.trap_oid, interface.oper_status_text, message
```

4.  Select a time field: `@timestamp`
5.  Add action: **Observability AI Assistant**
6.  **Message Template:**

```markdown
An SNMP linkDown trap alert has been triggered.

## Alert Query
FROM logs-snmp.trap-prod
| WHERE event.action == "interface-down"
| KEEP @timestamp, host.name, host.ip, event.action, message

## Investigation Tasks

### 1. Immediate Triage
- Which router reported the link down? (host.name)
- Which interface went down? (extract from message or varbinds)
- When did this occur? (@timestamp)

### 2. Impact Assessment
- Is this interface part of an OSPF adjacency?
- Query metrics-* for OSPF neighbor state on this router
- Check if any OSPF neighbors were lost after this timestamp

### 3. Correlation
- Are there other linkDown traps from the same router in the last 30 minutes?
- Are other routers (csr23-csr29) also reporting link issues?
- Is this a flapping interface? (check for linkUp followed by linkDown)

### 4. Network Context
Topology: 7 FRR routers in OSPF mesh
- CSR23 (172.20.20.23) - trap source, connects to CSR24, CSR25, CSR26, CSR27, CSR28
- CSR24-CSR29 are peer routers

### 5. Recommended Actions
Based on findings, suggest:
- If single interface down: Check physical connectivity, cable, port
- If multiple interfaces: Check router health, power, upstream switch
- If OSPF impacted: Verify traffic is rerouting via alternate paths

Provide a summary with severity assessment (Critical/High/Medium/Low).
```

7.  Optional: Add **Elastic-Cloud-SMTP** to receive an email.
8.  **Save** your rule.

## 12. Trigger a Failure

Use the provided script to simulate network events and prove Elastic can handle real-world scenarios. Choose menu 40 to generate **Interface eth1 DOWN** on CSR23.

Navigate to `/scripts` and execute:
```bash
./connect.sh
```

**Simulation Menu Options:**
*   **Option 40: Interface eth1 DOWN 🔴**
    *   Administratively shuts down the interface on CSR23.
    *   Sends an SNMP linkDown trap (OID `1.3.6.1.6.3.1.1.5.3`).
    *   Triggers OSPF reconvergence.
    *   Tests the entire observability pipeline.
*   **Option 41: Interface eth1 UP 🟢**
    *   Restores the interface.
    *   Sends an SNMP linkUp trap (OID `1.3.6.1.6.3.1.1.5.4`).
    *   Validates recovery detection.
*   **Option 46: Flap Interface (Down → Wait → Up) ⚡**
    *   Simulates an unstable link.
    *   Generates rapid-fire traps.
    *   Tests alert deduplication logic.
*   **Option 47: Watch for Traps (Live) 📊**
    *   Tails Logstash logs in real-time.
    *   Shows immediate feedback as traps arrive.
    *   Validates end-to-end pipeline.
*   **Option 48: Show CSR23 Interface Status 📋**
    *   Displays current interface states.
    *   Maps interfaces to OSPF neighbors.
    *   Provides context for troubleshooting.
*   **Option 49: Verify Trap Configuration 🔧**
    *   Checks SNMP trap setup.
    *   Tests connectivity to Logstash.
    *   Sends a test trap to validate the pipeline.

## 13. Kibana - Discover

**Discover** is the primary tool for exploring your Elasticsearch data in Kibana. Search and filter documents, analyze field structures, visualize patterns, and save findings to reuse later or share with dashboards. Whether investigating issues, analyzing trends, or validating data quality, Discover offers a flexible interface for understanding your data.

In our lab, we will use Discover to examine the incoming traps and gain insights into their data.
1.  Make sure you create a Data View for the index: `logs-snmp.trap-prod`.
2.  In **Discover**, choose your data view (`logs-snmp.trap-prod`) and search for: `1.3.6.1.6.3.1.1.5.3`.
3.  Open the flyout for one event, go to **Log overview**, and ask the assistant: *"What’s this message?"*

![Sample Log Event](Images/discover-log-overview.png)

**Expected results:**
![Assistant Response](Images/discover-ai-response.png)

## 14. AI Assistant

Head to the **AI Assistant** at the top right corner. In the flyout, select **Expand Conversation List** (top left corner).

![ai conversation](Images/conversation.png)

When your alert triggered, the prompt automatically generated an initial investigation.

See it for yourself:

![Assistant Investigation](Images/ai-assistant-summary.png)

**Well done! You have completed the lab.**

## 15. **What’s next?**

In upcoming blogs, we will explore how to parse data using **Streams**, build workflows with **One Workflow**, and leverage the **Agent Builder** (next-generation AI Assistant) to investigate and correlate events. Look out for the next blog in early 2026.
