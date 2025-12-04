#!/bin/bash

CONTAINER=${1:-clab-ospf-network-sw}

clear

echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Interface Dashboard - $CONTAINER"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Header
printf "%-15s | %-16s | %-8s | %-8s | %-10s\n" "Interface" "IP Address" "Admin" "Oper" "Traffic"
printf "%.15s-+-%.16s-+-%.8s-+-%.8s-+-%.10s\n" "---------------" "----------------" "--------" "--------" "----------"

# Get all interfaces
docker exec $CONTAINER ip -brief addr show 2>/dev/null | while read iface state addrs; do
    # Parse IP address
    ip="unassigned"
    for addr in $addrs; do
        if echo "$addr" | grep -q '^[0-9]'; then
            ip=$(echo "$addr" | cut -d'/' -f1)
            break
        fi
    done
    
    # Status icons
    if [ "$state" = "UP" ]; then
        admin="UP 🟢"
        oper="UP"
    else
        admin="DOWN 🔴"
        oper="DOWN"
    fi
    
    # Get traffic stats
    rx=$(docker exec $CONTAINER cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    tx=$(docker exec $CONTAINER cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    total=$((rx + tx))
    
    if [ $total -gt 1048576 ]; then
        traffic=$(awk "BEGIN {printf \"%.1f MB\", $total/1048576}")
    elif [ $total -gt 1024 ]; then
        traffic=$(awk "BEGIN {printf \"%.1f KB\", $total/1024}")
    else
        traffic="${total}B"
    fi
    
    printf "%-15s | %-16s | %-8s | %-8s | %-10s\n" "$iface" "$ip" "$admin" "$oper" "$traffic"
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Interface Counters"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

printf "%-15s | %12s | %12s | %10s\n" "Interface" "RX Packets" "TX Packets" "Errors"
printf "%.15s-+-%.12s-+-%.12s-+-%.10s\n" "---------------" "------------" "------------" "----------"

docker exec $CONTAINER ip -o link show 2>/dev/null | awk '{print $2}' | tr -d ':' | while read iface; do
    rx_packets=$(docker exec $CONTAINER cat /sys/class/net/$iface/statistics/rx_packets 2>/dev/null || echo 0)
    tx_packets=$(docker exec $CONTAINER cat /sys/class/net/$iface/statistics/tx_packets 2>/dev/null || echo 0)
    rx_errors=$(docker exec $CONTAINER cat /sys/class/net/$iface/statistics/rx_errors 2>/dev/null || echo 0)
    tx_errors=$(docker exec $CONTAINER cat /sys/class/net/$iface/statistics/tx_errors 2>/dev/null || echo 0)
    total_errors=$((rx_errors + tx_errors))
    
    # Only show interfaces with traffic
    if [ $rx_packets -gt 0 ] || [ $tx_packets -gt 0 ]; then
        printf "%-15s | %12s | %12s | %10s\n" "$iface" "$rx_packets" "$tx_packets" "$total_errors"
    fi
done

echo ""
echo "Usage: $0 [container-name]"
echo "Examples:"
echo "  $0                              # Default: clab-ospf-network-sw"
echo "  $0 clab-ospf-network-csr23     # Show router interfaces"
echo "  $0 clab-ospf-network-sw2       # Show second switch"

