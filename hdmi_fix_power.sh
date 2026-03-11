#!/bin/bash
#
# hdmi_fix_power.sh - Force NVIDIA GPU power on to restore HDMI detection
#
# On hybrid Intel/NVIDIA laptops, the NVIDIA GPU can enter runtime suspend
# (power/control = "auto"), which disables HDMI hotplug detection. This script
# forces the GPU to stay powered on and then checks if HDMI is detected.
#
# This is the least disruptive fix — no X session restart required.
# If this doesn't work, use hdmi_fix_reload.sh instead.
#
# Usage: sudo ./hdmi_fix_power.sh
#
# Effects:
#   - Sets /sys/bus/pci/devices/0000:01:00.0/power/control to "on"
#   - Slightly increases power consumption until next reboot or manual reset
#   - Non-destructive, does not restart any services

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NVIDIA_PCI="0000:01:00.0"
POWER_PATH="/sys/bus/pci/devices/$NVIDIA_PCI/power"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (sudo)${NC}"
    exit 1
fi

if [ ! -d "$POWER_PATH" ]; then
    echo -e "${RED}Error: NVIDIA PCI device $NVIDIA_PCI not found${NC}"
    exit 1
fi

echo -e "${GREEN}=== Force NVIDIA GPU Power On ===${NC}"
echo ""

# Show current state
BEFORE_STATUS=$(cat "$POWER_PATH/runtime_status")
BEFORE_CONTROL=$(cat "$POWER_PATH/control")
echo "Before:"
echo "  runtime_status: $BEFORE_STATUS"
echo "  power/control:  $BEFORE_CONTROL"
echo ""

# Force power on
echo "on" > "$POWER_PATH/control"
echo -e "${GREEN}Set power/control to 'on'${NC}"

# Wait for GPU to wake up
echo "Waiting 3 seconds for GPU to initialize..."
sleep 3

# Show new state
AFTER_STATUS=$(cat "$POWER_PATH/runtime_status")
AFTER_CONTROL=$(cat "$POWER_PATH/control")
echo ""
echo "After:"
echo "  runtime_status: $AFTER_STATUS"
echo "  power/control:  $AFTER_CONTROL"
echo ""

# Check HDMI
HDMI_STATUS=$(xrandr 2>/dev/null | grep 'HDMI-1-0' | awk '{print $2}' || echo "unknown")
if [ "$HDMI_STATUS" = "connected" ]; then
    echo -e "${GREEN}HDMI-1-0 is now CONNECTED${NC}"
    echo ""
    echo "To activate the display, run:"
    echo "  xrandr --output HDMI-1-0 --auto --right-of DP-2"
else
    echo -e "${YELLOW}HDMI-1-0 is still disconnected${NC}"
    echo ""
    echo "Power management was not the issue. Next step:"
    echo "  sudo ./hdmi_fix_reload.sh"
fi
echo ""
