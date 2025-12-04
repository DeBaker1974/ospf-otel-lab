#!/bin/bash

echo "========================================="
echo "LLDP Export Service Setup"
echo "========================================="
echo ""

SERVICE_NAME="lldp-export"
SCRIPT_PATH="$HOME/ospf-otel-lab/scripts/lldp-to-elasticsearch.sh"
LOG_PATH="$HOME/ospf-otel-lab/logs/lldp-export.log"

# Check if script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "✗ Script not found: $SCRIPT_PATH"
    exit 1
fi

# Check if .env exists
ENV_FILE="$HOME/ospf-otel-lab/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "✗ .env file not found"
    echo ""
    echo "Run: ./scripts/configure-elasticsearch.sh"
    exit 1
fi

# Create logs directory
mkdir -p "$HOME/ospf-otel-lab/logs"

echo "Creating systemd service..."
echo ""

# Create systemd service file
sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null <<SERVICEEOF
[Unit]
Description=LLDP to Elasticsearch Export Service (10s interval)
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/ospf-otel-lab
ExecStart=$SCRIPT_PATH
StandardOutput=append:$LOG_PATH
StandardError=append:$LOG_PATH
Restart=always
RestartSec=10
KillMode=process
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Reload systemd
sudo systemctl daemon-reload

# Enable service
sudo systemctl enable $SERVICE_NAME

# Start service
sudo systemctl start $SERVICE_NAME

# Wait a moment for service to start
sleep 3

# Check status
STATUS=$(sudo systemctl is-active $SERVICE_NAME)

echo ""
echo "========================================="
echo "Service Setup Complete"
echo "========================================="
echo ""

if [ "$STATUS" = "active" ]; then
    echo "✓ Service is running"
    echo ""
    echo "Service Details:"
    echo "  Name:     $SERVICE_NAME"
    echo "  Status:   Active"
    echo "  Script:   $SCRIPT_PATH"
    echo "  Logs:     $LOG_PATH"
    echo "  Interval: 10 seconds"
    echo ""
    echo "Commands:"
    echo "  Status:   sudo systemctl status $SERVICE_NAME"
    echo "  Stop:     sudo systemctl stop $SERVICE_NAME"
    echo "  Start:    sudo systemctl start $SERVICE_NAME"
    echo "  Restart:  sudo systemctl restart $SERVICE_NAME"
    echo "  Logs:     tail -f $LOG_PATH"
    echo "  Journal:  sudo journalctl -u $SERVICE_NAME -f"
    echo "  Disable:  sudo systemctl disable $SERVICE_NAME"
else
    echo "✗ Service failed to start"
    echo ""
    echo "Check logs:"
    echo "  sudo journalctl -u $SERVICE_NAME -n 50"
    echo "  tail -50 $LOG_PATH"
fi

echo ""
