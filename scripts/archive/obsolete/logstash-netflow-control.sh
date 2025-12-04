#!/bin/bash

LOGSTASH_CONTAINER="clab-ospf-network-logstash"
PIPELINE_PATH="/usr/share/logstash/pipeline/netflow.conf"
BACKUP_PATH="/usr/share/logstash/pipeline/netflow.conf.disabled"
ACTIVE_PATH="/usr/share/logstash/pipeline/netflow.conf.active"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

check_status() {
    echo "=================================================="
    echo "  Logstash NetFlow Pipeline Status"
    echo "=================================================="
    echo ""
    
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${LOGSTASH_CONTAINER}$"; then
        print_error "Logstash container not running"
        return 1
    fi
    
    # Check if pipeline file exists
    if docker exec $LOGSTASH_CONTAINER test -f $PIPELINE_PATH 2>/dev/null; then
        print_status "Pipeline file exists"
        
        # Check if it's disabled
        if docker exec $LOGSTASH_CONTAINER grep -q "# NetFlow pipeline disabled" $PIPELINE_PATH 2>/dev/null; then
            print_warning "Pipeline is DISABLED"
            STATUS="disabled"
        else
            # Check if UDP listener is active
            if docker exec $LOGSTASH_CONTAINER netstat -uln 2>/dev/null | grep -q 2055; then
                print_status "Pipeline is ACTIVE (listening on UDP 2055)"
                STATUS="active"
            else
                print_warning "Pipeline configured but not listening"
                STATUS="configured"
            fi
        fi
    else
        print_error "Pipeline file not found"
        STATUS="missing"
    fi
    
    echo ""
    echo "Current status: $STATUS"
    echo ""
    return 0
}

stop_pipeline() {
    echo "=================================================="
    echo "  Stopping Logstash NetFlow Pipeline"
    echo "=================================================="
    echo ""
    
    echo "1. Backing up current configuration..."
    docker exec $LOGSTASH_CONTAINER bash -c "
        if [ -f $PIPELINE_PATH ]; then
            if ! grep -q '# NetFlow pipeline disabled' $PIPELINE_PATH; then
                cp $PIPELINE_PATH $ACTIVE_PATH
                echo '  ✓ Backed up to $ACTIVE_PATH'
            else
                echo '  ⚠ Already disabled, no backup needed'
            fi
        fi
    "
    
    echo ""
    echo "2. Creating disabled configuration..."
    docker exec $LOGSTASH_CONTAINER bash -c "cat > $PIPELINE_PATH << 'EOF'
# NetFlow pipeline disabled
# Original config backed up to: $ACTIVE_PATH
# To re-enable, run: logstash-netflow-control.sh start

input {
  # NetFlow collection disabled
}

filter {
  # No filters
}

output {
  # Minimal output to keep pipeline valid
  stdout { codec => dots }
}
EOF"
    
    echo ""
    echo "3. Reloading Logstash configuration..."
    docker exec $LOGSTASH_CONTAINER kill -SIGHUP 1 2>/dev/null || {
        echo "   Restarting container instead..."
        docker restart $LOGSTASH_CONTAINER
        sleep 15
    }
    
    echo ""
    echo "4. Waiting for reload..."
    sleep 5
    
    echo ""
    echo "5. Verifying UDP port 2055 is released..."
    for i in {1..10}; do
        if docker exec $LOGSTASH_CONTAINER netstat -uln 2>/dev/null | grep -q 2055; then
            echo "   Waiting for port release... ($i/10)"
            sleep 2
        else
            print_status "Port 2055 released"
            break
        fi
    done
    
    echo ""
    print_status "NetFlow pipeline stopped"
    echo ""
}

start_pipeline() {
    echo "=================================================="
    echo "  Starting Logstash NetFlow Pipeline"
    echo "=================================================="
    echo ""
    
    echo "1. Checking for backup configuration..."
    if docker exec $LOGSTASH_CONTAINER test -f $ACTIVE_PATH 2>/dev/null; then
        echo "   Found backup configuration"
        docker exec $LOGSTASH_CONTAINER cp $ACTIVE_PATH $PIPELINE_PATH
        print_status "Restored from backup"
    else
        echo "   No backup found, creating new configuration..."
        create_default_config
    fi
    
    echo ""
    echo "2. Reloading Logstash configuration..."
    docker exec $LOGSTASH_CONTAINER kill -SIGHUP 1 2>/dev/null || {
        echo "   Restarting container instead..."
        docker restart $LOGSTASH_CONTAINER
        sleep 15
    }
    
    echo ""
    echo "3. Waiting for startup..."
    sleep 10
    
    echo ""
    echo "4. Verifying UDP listener..."
    for i in {1..10}; do
        if docker exec $LOGSTASH_CONTAINER netstat -uln 2>/dev/null | grep -q 2055; then
            print_status "UDP listener active on port 2055"
            break
        else
            echo "   Waiting for listener... ($i/10)"
            sleep 2
        fi
    done
    
    echo ""
    echo "5. Checking logs..."
    docker logs --tail 10 $LOGSTASH_CONTAINER 2>&1 | grep -E "Pipeline|UDP|netflow" | tail -5
    
    echo ""
    print_status "NetFlow pipeline started"
    echo ""
}

create_default_config() {
    docker exec $LOGSTASH_CONTAINER bash -c "cat > $PIPELINE_PATH << 'EOF'
input {
  udp {
    port => 2055
    codec => netflow {
      versions => [5, 9, 10]
    }
    workers => 2
  }
}

filter {
  # Add timestamp
  mutate {
    add_field => { \"[@metadata][target_index]\" => \"netflow-%{+YYYY.MM.dd}\" }
  }

  # Parse NetFlow version
  if [netflow][version] {
    mutate {
      add_field => { \"flow_version\" => \"%{[netflow][version]}\" }
    }
  }
}

output {
  # Debug output
  stdout {
    codec => rubydebug {
      metadata => true
    }
  }

  # Elasticsearch output
  elasticsearch {
    hosts => [\"elasticsearch:9200\"]
    index => \"netflow-%{+YYYY.MM.dd}\"
    user => \"elastic\"
    password => \"\${ELASTIC_PASSWORD}\"
    ssl => true
    ssl_certificate_verification => false
  }
}
EOF"
    print_status "Created default NetFlow configuration"
}

restart_pipeline() {
    echo "=================================================="
    echo "  Restarting Logstash NetFlow Pipeline"
    echo "=================================================="
    echo ""
    
    stop_pipeline
    sleep 5
    start_pipeline
}

show_logs() {
    echo "=================================================="
    echo "  Logstash NetFlow Pipeline Logs"
    echo "=================================================="
    echo ""
    
    LINES=${1:-50}
    
    docker logs --tail $LINES -f $LOGSTASH_CONTAINER 2>&1 | grep --line-buffered -E "netflow|UDP|flow|Pipeline|ERROR|WARN"
}

show_help() {
    cat << 'HELP'
================================================
  Logstash NetFlow Pipeline Control
================================================

Usage: logstash-netflow-control.sh [command]

Commands:
  status    - Show current pipeline status
  start     - Start/enable NetFlow pipeline
  stop      - Stop/disable NetFlow pipeline
  restart   - Restart NetFlow pipeline
  logs      - Follow NetFlow-related logs
  help      - Show this help message

Examples:
  ./logstash-netflow-control.sh status
  ./logstash-netflow-control.sh stop
  ./logstash-netflow-control.sh start
  ./logstash-netflow-control.sh logs

================================================
HELP
}

# Main script logic
case "${1:-help}" in
    status)
        check_status
        ;;
    start)
        check_status
        if [ "$STATUS" = "active" ]; then
            print_warning "Pipeline already active"
        else
            start_pipeline
        fi
        ;;
    stop)
        check_status
        if [ "$STATUS" = "disabled" ]; then
            print_warning "Pipeline already disabled"
        else
            stop_pipeline
        fi
        ;;
    restart)
        restart_pipeline
        ;;
    logs)
        show_logs ${2:-50}
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
