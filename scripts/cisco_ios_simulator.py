#!/usr/bin/env python3
"""
Cisco IOS Syslog Simulator for Elastic's Cisco IOS Integration.
Tailored for the ospf-network ContainerLab topology.

Sends realistic Cisco IOS syslog messages over UDP to an Elastic Agent
running the cisco_ios integration (syslog/UDP input).

Usage:
    python3 cisco_ios_simulator.py --host 172.20.20.50 --port 9001

Requirements:
    Python 3.8+  (no external dependencies)
"""

import argparse
import logging
import random
import socket
import time
from datetime import datetime, timezone
from dataclasses import dataclass
from typing import List, Optional

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LOG = logging.getLogger("cisco-ios-sim")

# ---------------------------------------------------------------------------
# Topology matching ospf-network.clab.yml
# ---------------------------------------------------------------------------

ROUTERS = [
    {
        "hostname": "csr28",
        "ip": "172.20.20.28",
        "loopback": "10.0.1.1",
        "interfaces": {
            "eth1": {"ip": "10.0.1.1/31",      "peer": "csr24", "cisco": "GigabitEthernet0/1"},
            "eth2": {"ip": "10.0.2.1/31",      "peer": "csr23", "cisco": "GigabitEthernet0/2"},
            "eth3": {"ip": "192.168.20.1/24",  "peer": "sw2",   "cisco": "GigabitEthernet0/3"},
        },
        "neighbors": ["csr24", "csr23"],
    },
    {
        "hostname": "csr24",
        "ip": "172.20.20.24",
        "loopback": "10.0.1.0",
        "interfaces": {
            "eth1": {"ip": "10.0.1.0/31",  "peer": "csr28", "cisco": "GigabitEthernet0/1"},
            "eth2": {"ip": "10.0.9.0/31",  "peer": "csr29", "cisco": "GigabitEthernet0/2"},
            "eth3": {"ip": "10.0.3.1/31",  "peer": "csr23", "cisco": "GigabitEthernet0/3"},
            "eth4": {"ip": "10.0.4.0/31",  "peer": "csr26", "cisco": "GigabitEthernet0/4"},
            "eth5": {"ip": "10.0.6.0/31",  "peer": "csr25", "cisco": "GigabitEthernet0/5"},
        },
        "neighbors": ["csr28", "csr29", "csr23", "csr26", "csr25"],
    },
    {
        "hostname": "csr23",
        "ip": "172.20.20.23",
        "loopback": "10.0.7.0",
        "interfaces": {
            "eth1": {"ip": "10.0.7.0/31",   "peer": "csr26", "cisco": "GigabitEthernet0/1"},
            "eth2": {"ip": "10.0.2.0/31",   "peer": "csr28", "cisco": "GigabitEthernet0/2"},
            "eth3": {"ip": "10.0.3.0/31",   "peer": "csr24", "cisco": "GigabitEthernet0/3"},
            "eth4": {"ip": "10.0.5.0/31",   "peer": "csr25", "cisco": "GigabitEthernet0/4"},
            "eth5": {"ip": "10.0.11.0/31",  "peer": "csr27", "cisco": "GigabitEthernet0/5"},
        },
        "neighbors": ["csr26", "csr28", "csr24", "csr25", "csr27"],
    },
    {
        "hostname": "csr29",
        "ip": "172.20.20.29",
        "loopback": "10.0.9.1",
        "interfaces": {
            "eth1": {"ip": "10.0.9.1/31",   "peer": "csr24", "cisco": "GigabitEthernet0/1"},
            "eth2": {"ip": "10.0.10.1/31",  "peer": "csr26", "cisco": "GigabitEthernet0/2"},
        },
        "neighbors": ["csr24", "csr26"],
    },
    {
        "hostname": "csr26",
        "ip": "172.20.20.26",
        "loopback": "10.0.10.0",
        "interfaces": {
            "eth1": {"ip": "10.0.10.0/31",    "peer": "csr29", "cisco": "GigabitEthernet0/1"},
            "eth2": {"ip": "10.0.7.1/31",     "peer": "csr23", "cisco": "GigabitEthernet0/2"},
            "eth3": {"ip": "10.0.4.1/31",     "peer": "csr24", "cisco": "GigabitEthernet0/3"},
            "eth4": {"ip": "10.0.8.1/31",     "peer": "csr25", "cisco": "GigabitEthernet0/4"},
            "eth5": {"ip": "192.168.10.3/24", "peer": "sw",    "cisco": "GigabitEthernet0/5"},
        },
        "neighbors": ["csr29", "csr23", "csr24", "csr25"],
    },
    {
        "hostname": "csr25",
        "ip": "172.20.20.25",
        "loopback": "10.0.5.1",
        "interfaces": {
            "eth1": {"ip": "10.0.5.1/31",     "peer": "csr23", "cisco": "GigabitEthernet0/1"},
            "eth2": {"ip": "10.0.6.1/31",     "peer": "csr24", "cisco": "GigabitEthernet0/2"},
            "eth3": {"ip": "10.0.8.0/31",     "peer": "csr26", "cisco": "GigabitEthernet0/3"},
            "eth4": {"ip": "10.0.12.0/31",    "peer": "csr27", "cisco": "GigabitEthernet0/4"},
            "eth5": {"ip": "192.168.10.2/24", "peer": "sw",    "cisco": "GigabitEthernet0/5"},
        },
        "neighbors": ["csr23", "csr24", "csr26", "csr27"],
    },
    {
        "hostname": "csr27",
        "ip": "172.20.20.27",
        "loopback": "10.0.11.1",
        "interfaces": {
            "eth1": {"ip": "10.0.11.1/31",  "peer": "csr23", "cisco": "GigabitEthernet0/1"},
            "eth2": {"ip": "10.0.12.1/31",  "peer": "csr25", "cisco": "GigabitEthernet0/2"},
        },
        "neighbors": ["csr23", "csr25"],
    },
]

# Build a lookup dict for quick neighbor resolution
_ROUTER_BY_NAME = {r["hostname"]: r for r in ROUTERS}

USERS = ["admin", "netops", "jsmith", "automated", "monitor", "noc-user"]
SOURCE_IPS = [
    "192.168.20.100",   # linux-top
    "192.168.10.20",    # linux-bottom
    "172.20.20.50",     # elastic-agent
    "172.20.20.31",     # logstash
]

ACL_NAMES = ["OUTSIDE_IN", "INSIDE_OUT", "MGMT_ACCESS", "DENY_ALL", "PERMIT_RFC1918", "WAN_FILTER"]
OSPF_PROCESS_ID = 1
BGP_AS_NUMBERS = [65000, 65001]
SNMP_COMMUNITIES = ["public", "monitoring", "netops-ro"]

# Syslog facility codes
FACILITY_LOCAL7 = 23  # Cisco IOS default


# ---------------------------------------------------------------------------
# Helpers — topology-aware randomisation
# ---------------------------------------------------------------------------

def _rand_router() -> dict:
    return random.choice(ROUTERS)


def _rand_iface(router: dict = None) -> str:
    """Return a Cisco-style interface name from the given (or random) router."""
    r = router or _rand_router()
    iface = random.choice(list(r["interfaces"].values()))
    return iface["cisco"]


def _rand_iface_and_peer(router: dict) -> tuple:
    """Return (cisco_iface, peer_ip) for a real link on this router."""
    eth_key = random.choice(list(router["interfaces"].keys()))
    iface_info = router["interfaces"][eth_key]
    peer_name = iface_info["peer"]
    peer_router = _ROUTER_BY_NAME.get(peer_name)
    peer_ip = peer_router["loopback"] if peer_router else "10.255.255.255"
    return iface_info["cisco"], peer_ip


def _rand_ip() -> str:
    return f"{random.choice([10, 172, 192])}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}"


def _rand_user() -> str:
    return random.choice(USERS)


def _rand_src_ip() -> str:
    return random.choice(SOURCE_IPS)


def _rand_acl() -> str:
    return random.choice(ACL_NAMES)


def _rand_vty() -> int:
    return random.randint(0, 15)


def _now_str() -> str:
    return datetime.now(timezone.utc).strftime("%H:%M:%S UTC %a %b %d %Y")


# ---------------------------------------------------------------------------
# Message Templates — realistic Cisco IOS syslog messages
# ---------------------------------------------------------------------------

@dataclass
class SyslogTemplate:
    facility: str
    severity: int       # 0-7
    mnemonic: str
    message_fn: callable  # (router) -> str
    weight: int = 10      # relative probability


# Every message_fn now takes a router dict so it can use real topology info.

TEMPLATES: List[SyslogTemplate] = [
    # ---- Interface events ----
    SyslogTemplate("LINEPROTO", 5, "UPDOWN",
        lambda r: f"Line protocol on Interface {_rand_iface(r)}, changed state to up",
        weight=20),
    SyslogTemplate("LINEPROTO", 5, "UPDOWN",
        lambda r: f"Line protocol on Interface {_rand_iface(r)}, changed state to down",
        weight=15),
    SyslogTemplate("LINK", 3, "UPDOWN",
        lambda r: f"Interface {_rand_iface(r)}, changed state to up",
        weight=15),
    SyslogTemplate("LINK", 3, "UPDOWN",
        lambda r: f"Interface {_rand_iface(r)}, changed state to down",
        weight=12),
    SyslogTemplate("LINK", 5, "CHANGED",
        lambda r: f"Interface {_rand_iface(r)}, changed state to administratively down",
        weight=5),

    # ---- Spanning Tree ----
    SyslogTemplate("SPANTREE", 5, "TOPOTRAP",
        lambda r: f"Topology Change Trap for vlan {random.randint(1, 200)}",
        weight=8),
    SyslogTemplate("SPANTREE", 5, "ROOTCHANGE",
        lambda r: f"Root changed for vlan {random.randint(1, 200)}: new root port is {_rand_iface(r)}",
        weight=3),

    # ---- OSPF (primary protocol in this lab) ----
    SyslogTemplate("OSPF", 5, "ADJCHG",
        lambda r: (lambda i, p: f"Process {OSPF_PROCESS_ID}, Nbr {p} on {i} from LOADING to FULL, Loading Done")(*_rand_iface_and_peer(r)),
        weight=18),
    SyslogTemplate("OSPF", 5, "ADJCHG",
        lambda r: (lambda i, p: f"Process {OSPF_PROCESS_ID}, Nbr {p} on {i} from FULL to DOWN, Neighbor Down: Dead timer expired")(*_rand_iface_and_peer(r)),
        weight=8),
    SyslogTemplate("OSPF", 4, "ERRRCV",
        lambda r: (lambda i, p: f"Process {OSPF_PROCESS_ID}, received invalid packet from {p} on {i}: mismatch area ID, from backbone area must be virtual-link")(*_rand_iface_and_peer(r)),
        weight=3),
    SyslogTemplate("OSPF", 5, "ADJCHG",
        lambda r: (lambda i, p: f"Process {OSPF_PROCESS_ID}, Nbr {p} on {i} from DOWN to INIT, Received Hello")(*_rand_iface_and_peer(r)),
        weight=6),
    SyslogTemplate("OSPF", 6, "FLOOD",
        lambda r: (lambda i, p: f"Process {OSPF_PROCESS_ID}, flooding LSA type 1 on {i}, adv router {r['loopback']}")(*_rand_iface_and_peer(r)),
        weight=10),
    SyslogTemplate("OSPF", 4, "MAXRETRANS",
        lambda r: (lambda i, p: f"Process {OSPF_PROCESS_ID}, max retransmissions exceeded for LSA type 1, LSID {r['loopback']}, on {i} to neighbor {p}")(*_rand_iface_and_peer(r)),
        weight=2),

    # ---- BGP (occasional) ----
    SyslogTemplate("BGP", 5, "ADJCHANGE",
        lambda r: f"neighbor {_rand_iface_and_peer(r)[1]} Up",
        weight=4),
    SyslogTemplate("BGP", 5, "ADJCHANGE",
        lambda r: f"neighbor {_rand_iface_and_peer(r)[1]} Down BGP Notification sent, hold time expired",
        weight=3),
    SyslogTemplate("BGP", 3, "NOTIFICATION",
        lambda r: f"received from neighbor {_rand_iface_and_peer(r)[1]} 6/4 (Administrative Reset) {random.randint(1, 10)} bytes",
        weight=2),

    # ---- HSRP ----
    SyslogTemplate("HSRP", 5, "STATECHANGE",
        lambda r: f"{_rand_iface(r)} Grp {random.randint(1, 10)} state Standby -> Active",
        weight=5),
    SyslogTemplate("HSRP", 5, "STATECHANGE",
        lambda r: f"{_rand_iface(r)} Grp {random.randint(1, 10)} state Active -> Standby",
        weight=4),

    # ---- ACL / Security ----
    SyslogTemplate("SEC", 6, "IPACCESSLOGP",
        lambda r: f"list {_rand_acl()} denied tcp {_rand_ip()}({random.randint(1024, 65535)}) -> {_rand_ip()}({random.choice([22, 23, 80, 443, 3389, 8080])}), {random.randint(1, 50)} packets",
        weight=25),
    SyslogTemplate("SEC", 6, "IPACCESSLOGP",
        lambda r: f"list {_rand_acl()} permitted tcp {_rand_ip()}({random.randint(1024, 65535)}) -> {_rand_ip()}({random.choice([80, 443])}), {random.randint(1, 20)} packets",
        weight=15),
    SyslogTemplate("SEC", 6, "IPACCESSLOGDP",
        lambda r: f"list {_rand_acl()} denied icmp {_rand_ip()} -> {_rand_ip()} ({random.choice(['8/0', '0/0', '3/3', '11/0'])}), {random.randint(1, 10)} packets",
        weight=10),

    # ---- Authentication / Login ----
    SyslogTemplate("SEC_LOGIN", 5, "LOGIN_SUCCESS",
        lambda r: f"Login Success [user: {_rand_user()}] [Source: {_rand_src_ip()}] [localport: 22] at {_now_str()}",
        weight=12),
    SyslogTemplate("SEC_LOGIN", 4, "LOGIN_FAILED",
        lambda r: f"Login failed [user: {random.choice(['hacker', 'test', 'unknown', _rand_user()])}] [Source: {_rand_ip()}] [localport: {random.choice([22, 23])}] [Reason: Invalid password] at {_now_str()}",
        weight=8),
    SyslogTemplate("SEC_LOGIN", 6, "QUIET_MODE_OFF",
        lambda r: f"Still timeleft for watching failures is {random.randint(30, 120)} secs, [user: {_rand_user()}] [Source: {_rand_src_ip()}] [localport: 22] [Reason: Login on successful authentication] at {_now_str()}",
        weight=3),

    # ---- SSH / VTY ----
    SyslogTemplate("SSH", 5, "SSH2_SESSION",
        lambda r: f"SSH2 Session request from {_rand_src_ip()} (tty = {_rand_vty()}) using crypto cipher 'aes256-ctr', hmac 'hmac-sha2-256' Succeeded",
        weight=8),
    SyslogTemplate("SSH", 3, "SSH2_SESSION",
        lambda r: f"SSH2 Session request from {_rand_ip()} (tty = {_rand_vty()}) using crypto cipher 'aes128-ctr', hmac 'hmac-sha1' Failed",
        weight=4),
    SyslogTemplate("LINE", 6, "USEREXEC",
        lambda r: f"User [{_rand_user()}] has activated exec session on vty{_rand_vty()} ({_rand_src_ip()})",
        weight=5),

    # ---- System / Config ----
    SyslogTemplate("SYS", 5, "CONFIG_I",
        lambda r: f"Configured from console by {_rand_user()} on vty{_rand_vty()} ({_rand_src_ip()})",
        weight=10),
    SyslogTemplate("SYS", 6, "LOGOUT",
        lambda r: f"User {_rand_user()} has exited tty session {_rand_vty()}({_rand_src_ip()})",
        weight=5),
    SyslogTemplate("SYS", 2, "MALLOCFAIL",
        lambda r: f"Memory allocation of {random.randint(1024, 65536)} bytes failed from 0x{random.randint(0x10000000, 0xFFFFFFFF):08X}, alignment 0, pool Processor",
        weight=1),
    SyslogTemplate("SYS", 1, "CPUHOG",
        lambda r: f"Task ran for {random.randint(2000, 8000)} msec ({random.randint(1, 50)}/{random.randint(1, 50)}), process = {random.choice(['IP Input', 'OSPF-1 Hello', 'OSPF-1 Router', 'ARP Input', 'SNMP ENGINE'])}",
        weight=2),
    SyslogTemplate("SYS", 6, "RESTART",
        lambda r: f"System restarted -- Cisco IOS Software, Version 17.06.05",
        weight=1),

    # ---- SNMP ----
    SyslogTemplate("SNMP", 5, "AUTHFAIL",
        lambda r: f"Authentication failure for SNMP req from host {_rand_ip()} community '{random.choice(SNMP_COMMUNITIES)}'",
        weight=5),
    SyslogTemplate("SNMP", 4, "TRAP",
        lambda r: f"SNMP trap linkDown sent for interface {_rand_iface(r)}",
        weight=4),

    # ---- DHCP ----
    SyslogTemplate("DHCPD", 6, "ASSIGN",
        lambda r: f"Assigned IP address {_rand_ip()} to client {':'.join(f'{random.randint(0, 255):02x}' for _ in range(6))} via {_rand_iface(r)}",
        weight=8),
    SyslogTemplate("DHCP_SNOOPING", 4, "DROP",
        lambda r: f"Dropping DHCP packet from {_rand_ip()} on untrusted port {_rand_iface(r)}: unauthorized DHCP server",
        weight=3),

    # ---- NTP ----
    SyslogTemplate("NTP", 5, "SYNC",
        lambda r: f"NTP clock is synchronized to {random.choice(['10.0.0.100', '172.20.20.1'])} stratum {random.randint(1, 4)}",
        weight=3),
    SyslogTemplate("NTP", 4, "UNSYNC",
        lambda r: f"NTP clock is unsynchronized, stratum set to 16",
        weight=2),

    # ---- Power / Environment ----
    SyslogTemplate("PLATFORM_ENV", 4, "FAN",
        lambda r: f"Fan {random.randint(1, 4)} in slot {random.randint(0, 2)} is {'running at high speed' if random.random() > 0.5 else 'not operational'}",
        weight=2),
    SyslogTemplate("PLATFORM_ENV", 2, "TEMP",
        lambda r: f"Temperature sensor {random.randint(1, 3)} has exceeded {random.choice(['warning', 'critical'])} threshold: {random.randint(55, 85)}C",
        weight=1),
    SyslogTemplate("PLATFORM_ENV", 6, "PSU",
        lambda r: f"Power supply {random.randint(1, 2)} is {'OK' if random.random() > 0.3 else 'not present'}",
        weight=2),

    # ---- CDP / LLDP ----
    SyslogTemplate("CDP", 5, "NATIVE_VLAN_MISMATCH",
        lambda r: f"Native VLAN mismatch discovered on {_rand_iface(r)} ({random.randint(1, 100)}), with {random.choice(r['neighbors'])} {_rand_iface()} ({random.randint(1, 100)})",
        weight=3),
    SyslogTemplate("CDP", 5, "DUPLEX_MISMATCH",
        lambda r: f"duplex mismatch discovered on {_rand_iface(r)} (not full duplex), with {random.choice(r['neighbors'])} {_rand_iface()} (full duplex)",
        weight=2),

    # ---- Crypto / VPN ----
    SyslogTemplate("CRYPTO", 6, "IKMP_SA_NEW",
        lambda r: f"IKE SA established {r['loopback']}:{random.randint(500, 4500)}->{_rand_ip()}:{random.randint(500, 4500)} Aggressive",
        weight=3),
    SyslogTemplate("CRYPTO", 4, "IKMP_SA_FAIL",
        lambda r: f"IKE SA negotiation failed with peer {_rand_ip()}: proposal mismatch",
        weight=2),

    # ---- Redundancy ----
    SyslogTemplate("REDUNDANCY", 5, "STATECHANGE",
        lambda r: f"Redundancy mode change to {random.choice(['SSO', 'RPR', 'STANDBY HOT'])}",
        weight=2),

    # ---- Generic ----
    SyslogTemplate("SYS", 6, "TTY_EXPIRE_TIMER",
        lambda r: f"(exec timer expired, tty {_rand_vty()}), user {_rand_user()}",
        weight=5),
]


# ---------------------------------------------------------------------------
# Syslog message formatter
# ---------------------------------------------------------------------------

class CiscoIOSSyslogFormatter:
    """Formats messages in standard Cisco IOS syslog format."""

    def __init__(self):
        self._seq = 0

    def format(self, router: dict, template: SyslogTemplate) -> str:
        self._seq += 1

        priority = FACILITY_LOCAL7 * 8 + template.severity
        timestamp = datetime.now(timezone.utc).strftime("%b %d %H:%M:%S.%f")[:-3]
        hostname = router["hostname"]
        message_body = template.message_fn(router)

        if random.random() > 0.3:
            # With sequence number (most common on modern IOS)
            msg = (
                f"<{priority}>{self._seq}: "
                f"{hostname}: "
                f"*{timestamp} UTC: "
                f"%{template.facility}-{template.severity}-{template.mnemonic}: "
                f"{message_body}"
            )
        else:
            # Without sequence number (legacy style)
            msg = (
                f"<{priority}>"
                f"{hostname}: "
                f"{timestamp} UTC: "
                f"%{template.facility}-{template.severity}-{template.mnemonic}: "
                f"{message_body}"
            )

        return msg


# ---------------------------------------------------------------------------
# Scenario engine — topology-aware correlated event bursts
# ---------------------------------------------------------------------------

class ScenarioEngine:
    """Generates correlated event bursts using real topology relationships."""

    def __init__(self, formatter: CiscoIOSSyslogFormatter):
        self.formatter = formatter
        self.scenarios = [
            self._interface_flap,
            self._bgp_session_reset,
            self._failed_login_burst,
            self._config_change_session,
            self._ospf_neighbor_flap,
            self._link_failure_cascade,
            self._ospf_area_mismatch,
            self._convergence_event,
        ]

    def maybe_trigger(self) -> Optional[List[str]]:
        """Randomly triggers a scenario (~5% chance per tick)."""
        if random.random() < 0.05:
            scenario = random.choice(self.scenarios)
            router = random.choice(ROUTERS)
            LOG.info(f"🎬 Triggering scenario: {scenario.__name__} on {router['hostname']}")
            return scenario(router)
        return None

    def _get_real_link(self, router: dict) -> tuple:
        """Returns (cisco_iface, peer_hostname, peer_ip) for a real link."""
        eth_key = random.choice(list(router["interfaces"].keys()))
        info = router["interfaces"][eth_key]
        peer_name = info["peer"]
        peer_router = _ROUTER_BY_NAME.get(peer_name)
        peer_ip = peer_router["loopback"] if peer_router else "10.255.255.255"
        return info["cisco"], peer_name, peer_ip

    def _interface_flap(self, router: dict) -> List[str]:
        """Interface goes down then comes back up on a real link."""
        cisco_iface, peer_name, _ = self._get_real_link(router)
        msgs = []
        for facility, sev, state in [
            ("LINK", 3, "down"),
            ("LINEPROTO", 5, "down"),
            ("LINEPROTO", 5, "up"),
            ("LINK", 3, "up"),
        ]:
            prefix = "Line protocol on " if facility == "LINEPROTO" else ""
            t = SyslogTemplate(facility, sev, "UPDOWN",
                lambda r, p=prefix, i=cisco_iface, s=state: f"{p}Interface {i}, changed state to {s}")
            msgs.append(self.formatter.format(router, t))
        return msgs

    def _bgp_session_reset(self, router: dict) -> List[str]:
        """BGP hold timer expires and session re-establishes."""
        _, peer_name, peer_ip = self._get_real_link(router)
        return [
            self.formatter.format(router, SyslogTemplate("BGP", 5, "ADJCHANGE",
                lambda r, p=peer_ip: f"neighbor {p} Down BGP Notification sent, hold time expired")),
            self.formatter.format(router, SyslogTemplate("BGP", 3, "NOTIFICATION",
                lambda r, p=peer_ip: f"sent to neighbor {p} 4/0 (Hold Timer Expired) 0 bytes")),
            self.formatter.format(router, SyslogTemplate("BGP", 5, "ADJCHANGE",
                lambda r, p=peer_ip: f"neighbor {p} Up")),
        ]

    def _failed_login_burst(self, router: dict) -> List[str]:
        """Brute force login attempt from a single attacker IP."""
        attacker_ip = _rand_ip()
        count = random.randint(3, 8)
        return [
            self.formatter.format(router, SyslogTemplate("SEC_LOGIN", 4, "LOGIN_FAILED",
                lambda r, a=attacker_ip: f"Login failed [user: admin] [Source: {a}] [localport: 22] [Reason: Invalid password] at {_now_str()}"))
            for _ in range(count)
        ]

    def _config_change_session(self, router: dict) -> List[str]:
        """Full SSH login → config change → logout sequence."""
        user = _rand_user()
        src = _rand_src_ip()
        vty = _rand_vty()
        return [
            self.formatter.format(router, SyslogTemplate("SSH", 5, "SSH2_SESSION",
                lambda r, s=src, v=vty: f"SSH2 Session request from {s} (tty = {v}) using crypto cipher 'aes256-ctr', hmac 'hmac-sha2-256' Succeeded")),
            self.formatter.format(router, SyslogTemplate("SEC_LOGIN", 5, "LOGIN_SUCCESS",
                lambda r, u=user, s=src: f"Login Success [user: {u}] [Source: {s}] [localport: 22] at {_now_str()}")),
            self.formatter.format(router, SyslogTemplate("SYS", 5, "CONFIG_I",
                lambda r, u=user, v=vty, s=src: f"Configured from console by {u} on vty{v} ({s})")),
            self.formatter.format(router, SyslogTemplate("SYS", 6, "LOGOUT",
                lambda r, u=user, v=vty, s=src: f"User {u} has exited tty session {v}({s})")),
        ]

    def _ospf_neighbor_flap(self, router: dict) -> List[str]:
        """OSPF adjacency drops and re-forms — using real neighbor topology."""
        cisco_iface, peer_name, peer_ip = self._get_real_link(router)
        pid = OSPF_PROCESS_ID
        return [
            self.formatter.format(router, SyslogTemplate("OSPF", 5, "ADJCHG",
                lambda r, p=peer_ip, i=cisco_iface: f"Process {pid}, Nbr {p} on {i} from FULL to DOWN, Neighbor Down: Dead timer expired")),
            self.formatter.format(router, SyslogTemplate("OSPF", 5, "ADJCHG",
                lambda r, p=peer_ip, i=cisco_iface: f"Process {pid}, Nbr {p} on {i} from DOWN to INIT, Received Hello")),
            self.formatter.format(router, SyslogTemplate("OSPF", 5, "ADJCHG",
                lambda r, p=peer_ip, i=cisco_iface: f"Process {pid}, Nbr {p} on {i} from EXSTART to EXCHANGE, Negotiation Done")),
            self.formatter.format(router, SyslogTemplate("OSPF", 5, "ADJCHG",
                lambda r, p=peer_ip, i=cisco_iface: f"Process {pid}, Nbr {p} on {i} from LOADING to FULL, Loading Done")),
        ]

    def _link_failure_cascade(self, router: dict) -> List[str]:
        """Link goes down → SNMP trap → OSPF neighbor loss on same interface."""
        cisco_iface, peer_name, peer_ip = self._get_real_link(router)
        pid = OSPF_PROCESS_ID
        return [
            self.formatter.format(router, SyslogTemplate("LINK", 3, "UPDOWN",
                lambda r, i=cisco_iface: f"Interface {i}, changed state to down")),
            self.formatter.format(router, SyslogTemplate("LINEPROTO", 5, "UPDOWN",
                lambda r, i=cisco_iface: f"Line protocol on Interface {i}, changed state to down")),
            self.formatter.format(router, SyslogTemplate("SNMP", 4, "TRAP",
                lambda r, i=cisco_iface: f"SNMP trap linkDown sent for interface {i}")),
            self.formatter.format(router, SyslogTemplate("OSPF", 5, "ADJCHG",
                lambda r, p=peer_ip, i=cisco_iface: f"Process {pid}, Nbr {p} on {i} from FULL to DOWN, Neighbor Down: Interface down")),
        ]

    def _ospf_area_mismatch(self, router: dict) -> List[str]:
        """Simulates an OSPF configuration error — area mismatch with neighbor."""
        cisco_iface, peer_name, peer_ip = self._get_real_link(router)
        pid = OSPF_PROCESS_ID
        return [
            self.formatter.format(router, SyslogTemplate("OSPF", 4, "ERRRCV",
                lambda r, p=peer_ip, i=cisco_iface: f"Process {pid}, received invalid packet from {p} on {i}: mismatch area ID, area {random.choice(['0.0.0.0', '0.0.0.1'])} in the header must be area 0.0.0.0")),
            self.formatter.format(router, SyslogTemplate("OSPF", 4, "ERRRCV",
                lambda r, p=peer_ip, i=cisco_iface: f"Process {pid}, received invalid packet from {p} on {i}: mismatch authentication type")),
        ]

    def _convergence_event(self, router: dict) -> List[str]:
        """Simulates OSPF SPF recalculation after topology change."""
        pid = OSPF_PROCESS_ID
        return [
            self.formatter.format(router, SyslogTemplate("OSPF", 6, "SPF",
                lambda r: f"Process {pid}, SPF calculation scheduled, change in LSA type 1, LSID {r['loopback']}, adv {random.choice(ROUTERS)['loopback']}")),
            self.formatter.format(router, SyslogTemplate("OSPF", 6, "SPF",
                lambda r: f"Process {pid}, SPF completed in {random.randint(1, 50)}ms, routes: {random.randint(5, 25)} intra, {random.randint(0, 5)} inter")),
        ]


# ---------------------------------------------------------------------------
# Main sender loop
# ---------------------------------------------------------------------------

class CiscoIOSSimulator:
    """Main simulator that sends syslog UDP packets."""

    def __init__(self, host: str, port: int, eps: float = 5.0, burst_max: int = 3):
        self.host = host
        self.port = port
        self.eps = eps
        self.burst_max = burst_max
        self.formatter = CiscoIOSSyslogFormatter()
        self.scenario_engine = ScenarioEngine(self.formatter)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._total_sent = 0

    def _pick_template(self) -> SyslogTemplate:
        """Weighted random selection of a message template."""
        total_weight = sum(t.weight for t in TEMPLATES)
        r = random.randint(1, total_weight)
        cumulative = 0
        for t in TEMPLATES:
            cumulative += t.weight
            if r <= cumulative:
                return t
        return TEMPLATES[-1]

    def _send(self, message: str):
        """Send a single syslog UDP datagram."""
        try:
            self.sock.sendto(message.encode("utf-8"), (self.host, self.port))
            self._total_sent += 1
            LOG.debug(f"[{self._total_sent}] → {message[:120]}...")
        except OSError as e:
            LOG.error(f"Send failed: {e}")

    def run(self):
        """Main loop — runs until interrupted."""
        LOG.info(f"🚀 Cisco IOS Syslog Simulator starting")
        LOG.info(f"   Target:       {self.host}:{self.port} (UDP)")
        LOG.info(f"   Rate:         ~{self.eps} events/sec")
        LOG.info(f"   Routers:      {', '.join(r['hostname'] for r in ROUTERS)}")
        LOG.info(f"   Templates:    {len(TEMPLATES)} message types")
        LOG.info(f"   Scenarios:    {len(self.scenario_engine.scenarios)} correlated event types")
        LOG.info(f"   Press Ctrl+C to stop\n")

        try:
            while True:
                # --- Possibly trigger a correlated scenario ---
                scenario_msgs = self.scenario_engine.maybe_trigger()
                if scenario_msgs:
                    for msg in scenario_msgs:
                        self._send(msg)
                        time.sleep(random.uniform(0.05, 0.3))

                # --- Send a random burst of individual events ---
                burst_size = random.randint(1, self.burst_max)
                for _ in range(burst_size):
                    router = random.choice(ROUTERS)
                    template = self._pick_template()
                    message = self.formatter.format(router, template)
                    self._send(message)

                # --- Pace to approximate target EPS ---
                sleep_time = burst_size / self.eps * random.uniform(0.8, 1.2)
                time.sleep(sleep_time)

                # --- Periodic status ---
                if self._total_sent % 100 == 0:
                    LOG.info(f"📊 Total messages sent: {self._total_sent}")

        except KeyboardInterrupt:
            LOG.info(f"\n🛑 Stopped. Total messages sent: {self._total_sent}")
        finally:
            self.sock.close()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Cisco IOS Syslog Simulator — tailored for ospf-network ContainerLab",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Send to Elastic Agent in the ContainerLab topology
  python3 cisco_ios_simulator.py --host 172.20.20.50 --port 9001

  # Higher throughput for load testing
  python3 cisco_ios_simulator.py --host 172.20.20.50 --port 9001 --eps 50

  # Low-volume background simulation
  python3 cisco_ios_simulator.py --host 172.20.20.50 --port 9001 --eps 0.5

  # Verbose output for debugging
  python3 cisco_ios_simulator.py --host 172.20.20.50 --port 9001 -v
        """,
    )
    parser.add_argument("--host", default="172.20.20.50",
                        help="Elastic Agent host (default: 172.20.20.50)")
    parser.add_argument("--port", type=int, default=9001,
                        help="Syslog UDP port (default: 9001)")
    parser.add_argument("--eps", type=float, default=5.0,
                        help="Target events per second (default: 5)")
    parser.add_argument("--burst-max", type=int, default=3,
                        help="Max events per burst (default: 3)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Show each message sent")

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    sim = CiscoIOSSimulator(
        host=args.host,
        port=args.port,
        eps=args.eps,
        burst_max=args.burst_max,
    )
    sim.run()


if __name__ == "__main__":
    main()