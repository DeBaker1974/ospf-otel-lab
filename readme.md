# Containerlab OSPF Simulation with OTEL, NetFlow, and SNMP, shipping to Elasticsearch

## Introduction:

This lab provides a self-contained, reproducible **Containerlab** simulation of an **OSPF Area 0** network core. It features a mesh of 7 **FRR routers** and two Ubuntu hosts to simulate end-user traffic.

The primary focus is on comprehensive network observability, integrating three distinct data pipelines into a managed **Elastic Cloud** stack:

* **SNMP Polling (Metrics):** Collected via an **OTEL Collector**.  
* **NetFlow (Traffic Analysis):** Exported from all routers and collected by an **Elastic Agent**.  
* **SNMP Traps (Events/Logs):** Sent from csr23 and processed by **Logstash**.

Use case implemented:
- Simulate SNMP Traps for CSR23 (eth1 down/up). Recover the trap in elastic.
- Simulate CSR23 down/up. Visualize the status in the "CSR23 - Interface Status" dashboard

![Lab Topology](Images/lab-topology.jpg)

# Quick Start:

- Suggested instance for deployment:  
* GCP: e2-standard-2 (2 vCPU, 1 core, 8 GB memory)  
* AWS: t3.large 2 vCPU, 8 GB memory  
* Azure: Standard\_B2ms, 2 vCPU, 8GB memory  
- Download the folder:  
  - [DeBaker1974/Containerlab-OSPF: Containerlab OSPF Simulation with OTEL, NetFlow, and SNMP](https://github.com/DeBaker1974/Containerlab-OSPF)  
- Get the following:  
  - Elasticsearch endpoint and Api Key  
  - Fleet Url and Token from a policy  
- Run the following scripts:
  - cd ospf-otel-lab/scripts
  - chmod \+x \*
  - ./install-lab-prereqs.sh
  - ./configure-elasticsearch.sh
  - ./complete-setup.sh
- Import the kibana dashboard "CSR23 - Interface Status"

### 1\. High-Level Architecture

**•**	**Infrastructure:** Containerlab (Docker-based).  
**•**	**Routing Protocol:** OSPF Area 0 (Single Area).  
**•**	**Core Functions:** A mesh of 7 FRR routers simulating a Service Provider or Enterprise Core.  
**•**	**Edge Functions:** Ubuntu hosts simulating end-user traffic (Top/Bottom).  
**•**	**Observability Stack:** Elastic Stack (Cloud) receiving data via OTEL Collector, Logstash, and Elastic Agent.  
──────────────────────────────────────────────────

### 2\. Node Roles & Management IPs

All nodes sit on the clab management network: **172.20.20.0/24**.

| Node Name | Type | Mgmt IP | Role |
| :---: | :---: | :---: | :---: |
| **csr28** | FRR Router | .28 | **Top Hub / Core**. Gateway for Top Network. |
| **csr23** | FRR Router | .23 | **Core Router**. Metrics, **SNMP Trap Source**. |
| **csr24** | FRR Router | .24 | **Core Router**. Heavy mesh connectivity. |
| **csr25** | FRR Router | .25 | **Bottom Distribution**. Gateway for Bottom Network. |
| **csr26** | FRR Router | .26 | **Bottom Distribution**. Gateway for Bottom Network. |
| **csr27** | FRR Router | .27 | **Right Wing / Edge**. |
| **csr29** | FRR Router | .29 | **Left Wing / Edge**. |
| **linux-top** | Ubuntu Host | N/A  | End User (Top). Data IP: 192.168.20.100. |
| **linux-bottom** | Ubuntu Host | N/A  | End User (Bottom). Data IP: 192.168.10.20. |
| **elastic-agent** | Elastic Agent | .50 | **NetFlow Collector** (Port 2055). |
| **otel-col** | OTEL Contrib | Auto | **SNMP Poller**. Sends to Elastic Cloud. |
| **logstash** | Logstash | .31 | **SNMP Trap Receiver** (Port 1062). Sends to Elastic Cloud. |

──────────────────────────────────────────────────

### 3\. Physical & Data Plane Topology

The network is structured as a vertical flow with a redundant core mesh.

#### *\*\*A. North (Top) Sector\*\**

**•**	**Components:** linux-top → sw2 → csr28.  
**•**	**Access Switch (sw2):**  
**•**	Connects linux-top (eth1).  
**•**	Connects elastic-agent-sw2 (eth1).  
**•**	Uplink to csr28 (eth3).  
**•**	**Subnet:** 192.168.20.0/24 (Gateway: csr28 IP .1).

#### *\*\*B. The Core Mesh (OSPF Area 0)\*\**

Routers connect via point-to-point **/31** links.

**•**	**CSR28 (Top Hub):**  
**•**	Down to csr24.  
**•**	Down to csr23.  
**•**	**CSR24 (Left Core):**  
**•**	Connects to csr28 (Up), csr23 (Cross), csr29 (Left Edge), csr26 (Down Left), csr25 (Down Right).  
**•**	**CSR23 (Right Core):**  
**•**	Connects to csr28 (Up), csr24 (Cross), csr27 (Right Edge), csr26 (Down Left), csr25 (Down Right).  
**•**	**CSR29 (Left Edge):**  
**•**	Connects to csr24 & csr26.  
**•**	**CSR27 (Right Edge):**  
**•**	Connects to csr23 & csr25.

#### *\*\*C. South (Bottom) Sector\*\**

**•**	**Router Layer:** csr25 and csr26 act as redundant gateways.  
**•**	**Access Switch (sw):**  
**•**	Uplink from csr25 (eth5).  
**•**	Uplink from csr26 (eth5).  
**•**	Connects linux-bottom (eth1).  
**•**	**Subnet:** 192.168.10.0/24 (VRRP or ECMP style gateway on Routers .2 and .3).  
──────────────────────────────────────────────────

### 4\. Telemetry & Observability Architecture

Your setup uses three distinct pipelines flowing into **Elastic Cloud .**

#### *\*\*Pipeline 1: SNMP Polling (Metrics)\*\**

**•**	**Method:** Active Polling.  
**•**	**Source:** otel-collector (Container).  
**•**	**Targets:** All 7 Routers (172.20.20.23 \- .29) on **UDP 161**.  
**•**	**Data Types:**  
**•**	System Uptime, Memory.  
**•**	Interface Stats (In/Out Bytes, Errors).  
**•**	LLDP Neighbors.  
**•**	TCP/UDP/IP/ARP Stats (Specific to csr28).  
**•**	**Destination:** Elastic Cloud (Indices: metrics-snmp.\*).

#### *\*\*Pipeline 2: NetFlow (Traffic Analysis)\*\**

**•**	**Method:** Push (Exporter).  
**•**	**Source:** All Routers (via softflowd installed by netflow-startup.sh).  
**•**	**Target:** elastic-agent-sw2 (172.20.20.50) on **UDP 2055**.  
**•**	**Data Types:** IP Flow data (5-tuple).  
**•**	**Integration:** Fleet-managed Elastic Agent (Network Packet Capture integration).

#### *\*\*Pipeline 3: SNMP Traps (Events/Logs)\*\**

**•**	**Method:** Push (Trap/Notification).  
**•**	**Source:** Explicitly configured on **csr23** only (per snmpd.conf).  
**•**	**Configuration:** trap2sink 172.20.20.31:1062.  
**•**	**Triggers:** Interface Up/Down events (monitored eth1 through eth5).  
**•**	**Target:** logstash (172.20.20.31) on **UDP 1062**.  
**•**	**Processing:** Logstash maps OIDs to human-readable events (e.g., "Interface down on csr23").  
**•**	**Destination:** Elastic Cloud (Data Stream: logs-snmp.trap-prod).  
──────────────────────────────────────────────────

### 5\. Routing Logic (OSPF)

From frr.conf:

**•**	**Router ID:** Loopback IP 10.255.0.X (e.g., 10.255.0.23).  
**•**	**Area:** All interfaces are in **Area 0**.  
**•**	**Network Type:** point-to-point is explicitly configured on links to reduce OSPF overhead (no DR/BDR election).

## 3\. Directory Structure

Ensure your project directory (\~/ospf-otel-lab) looks like this before starting:

```
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
    ├── scripts
    │   ├── ./connect.sh
    │   └── ./complete-setup.sh
    │   └── ./configure-elasticsearch.sh
    └── Archive


```

──────────────────────────────────────────────────

## 4\. Deployment Steps

### Step 1: Install Dependencies

Run the prerequisite script to install Docker CE and Containerlab.

cd \~/ospf-otel-lab   
chmod \+x scripts/install-lab-prereqs.sh   
./scripts/install-lab-prereqs.sh   
 

*\*\*⚠️ IMPORTANT:\*\* You must \*\*Log Out\*\* and \*\*Log Back In\*\* after this step for Docker group permissions to take effect.*

──────────────────────────────────────────────────

### Step 2: Configure Elastic Cloud Connection

Set up your connection to the Elastic Stack. This script validates your credentials and auto-configures the specific versions for the lab.

Obtain your **Elasticsearch Endpoint** (HTTPS URL).  
Create a **Base64 Encoded API Key** in Kibana (Stack Management → Security → API Keys).  
Create a Fleet policy which with Netflow Capture  
Obtain the Fleet URL and the policy token.

Run the configuration wizard:

chmod \+x scripts/configure-elasticsearch.sh   
./scripts/configure-elasticsearch.sh   
 

**What this does:**

**•**	Tests connectivity to Elastic Cloud.  
**•**	Detects if you are using Serverless or Traditional Elastic.  
**•**	Generates a local .env file used by the deployment script.  
**•**	Hardcode different configuration files with your credentials.  
──────────────────────────────────────────────────

### Step 3: Deploy the Network

Run the master deployment script. This is a "Zero-Touch" deployment that builds the entire topology and configures telemetry.

chmod \+x scripts/complete-setup.sh   
./scripts/complete-setup.sh   
 

**This process takes approximately 12-15 minutes.**

**•**	**Cleanup:** Removes old containers and network bridges.  
**•**	**Deploy:** Launches 14 containers defined in ospf-network.clab.yml.  
**•**	**Bootstrap:** Installs snmpd, lldpd, and softflowd inside the FRR routers.  
**•**	**Configure:** Enables SNMP AgentX for LLDP integration.  
**•**	**Converge:** Waits for OSPF adjacencies to form.  
**•**	**Verify:** Checks data flow for SNMP, LLDP, and Traps.  
──────────────────────────────────────────────────

## 5\. Verification & Access

### Lab Status Summary

At the end of the deployment, the script provides a health summary:

**•**	**SNMP:** Should show 7/7 routers responding.  
**•**	**LLDP:** Should show neighbor relationships detected via SNMP.  
**•**	**Elasticsearch:** Should verify data ingestion counts (Metrics & Logs).

### Accessing Devices

**•**	**Routers (VTysh):**

docker exec \-it clab-ospf-network-csr28 vtysh   
 

**•**	**Linux Clients:**

docker exec \-it clab-ospf-network-linux-top bash   
 

**•**	**Logstash Logs:**

docker logs \-f clab-ospf-network-logstash   
 

──────────────────────────────────────────────────

## 6\. Telemetry Data Flow

| Data Type | Source | Transport | Collector | Destination |
| :---- | :---: | :---: | :---: | :---: |
| **Metrics** | FRR Routers | UDP 161 (SNMP) | OTEL Collector | metrics-snmp.\* |
| **Traps** | CSR23 | UDP 1062 (SNMP Trap) | Logstash | logs-snmp.trap-\* |
| **NetFlow** | All Routers | UDP 2055 (NetFlow v5) | Elastic Agent | logs-network\_traffic.\* |
| **Topology** | FRR Routers | AgentX (LLDP) | OTEL Collector | lldp-topology |

──────────────────────────────────────────────────

## 7\. Notes

Use the ./scripts/connect.sh to access the different resources of the lab

#### 8\. net-lldp-edges

Index Mapping and Transform :

* You will need the setup to complete before executing this transform.  
* You need to have lldp data coming in.  
* You need to have the lldp-topology index for the transform to work

**Create mapping:**

```
PUT net-lldp-edges
{
  "mappings": {
    "properties": {
      "src_router": {
        "type": "keyword"
      },
      "dst_router": {
        "type": "keyword"
      },
      "last_seen": {
        "type": "date"
      },
      "first_seen": {
        "type": "date"
      },
      "observation_count": {
        "type": "long"
      },
      "neighbor_count": {
        "type": "long"
      }
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

```

PUT _transform/lldp-topology-to-edges
{
  "source": {
    "index": ["metrics-lldp-prod"],
    "query": {
      "bool": {
        "must": [
          {
            "exists": {
              "field": "network.lldp.rem.sysname"
            }
          }
        ],
        "must_not": [
          {
            "term": {
              "network.lldp.rem.sysname": ""
            }
          }
        ]
      }
    }
  },
  "dest": {
    "index": "net-lldp-edges"
  },
  "frequency": "1m",
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "60s"
    }
  },
  "pivot": {
    "group_by": {
      "src_router": {
        "terms": {
          "field": "host.name"
        }
      },
      "dst_router": {
        "terms": {
          "field": "network.lldp.rem.sysname"
        }
      }
    },
    "aggregations": {
      "last_seen": {
        "max": {
          "field": "@timestamp"
        }
      },
      "first_seen": {
        "min": {
          "field": "@timestamp"
        }
      },
      "observation_count": {
        "value_count": {
          "field": "@timestamp"
        }
      },
      "neighbor_count": {
        "max": {
          "field": "network.lldp.neighbors"
        }
      }
    }
  },
  "description": "LLDP network topology - router-to-router connections (simplified)",
  "settings": {
    "max_page_search_size": 500
  }
}
```
