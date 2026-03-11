#!/bin/bash
#
# hdmi_activate.sh - Activate an already-detected HDMI monitor
#
# Use this after HDMI-1-0 shows "connected" in xrandr but is not yet active
# (no picture on the monitor). Places the HDMI display to the right of DP-2.
#
# No root required. Safe to run at any time.
#
# Usage: ./hdmi_activate.sh [position]
#
# Arguments:
#   position  Where to place the HDMI monitor relative to DP-2.
#             Options: right (default), left, mirror, above, below
#
# Examples:
#   ./hdmi_activate.sh           # right of DP-2 (default)
#   ./hdmi_activate.sh left      # left of DP-2
#   ./hdmi_activate.sh mirror    # clone DP-2

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HDMI_OUTPUT="HDMI-1-0"
REFERENCE="DP-2"
POSITION="${1:-right}"

# Check HDMI status
HDMI_STATUS=$(xrandr 2>/dev/null | grep "$HDMI_OUTPUT" | awk '{print $2}')

if [ "$HDMI_STATUS" != "connected" ]; then
    echo -e "${RED}$HDMI_OUTPUT is not connected (status: ${HDMI_STATUS:-not found})${NC}"
    echo ""
    echo "Run ./hdmi_diagnose.sh to troubleshoot."
    exit 1
fi

# Check if already active
if xrandr --listmonitors 2>/dev/null | grep -q "$HDMI_OUTPUT"; then
    echo -e "${YELLOW}$HDMI_OUTPUT is already active:${NC}"
    xrandr --listmonitors | grep "$HDMI_OUTPUT"
    echo ""
    read -p "Reconfigure anyway? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Apply position
case "$POSITION" in
    right)
        echo "Placing $HDMI_OUTPUT to the right of $REFERENCE..."
        xrandr --output "$HDMI_OUTPUT" --auto --right-of "$REFERENCE"
        ;;
    left)
        echo "Placing $HDMI_OUTPUT to the left of $REFERENCE..."
        xrandr --output "$HDMI_OUTPUT" --auto --left-of "$REFERENCE"
        ;;
    above)
        echo "Placing $HDMI_OUTPUT above $REFERENCE..."
        xrandr --output "$HDMI_OUTPUT" --auto --above "$REFERENCE"
        ;;
    below)
        echo "Placing $HDMI_OUTPUT below $REFERENCE..."
        xrandr --output "$HDMI_OUTPUT" --auto --below "$REFERENCE"
        ;;
    mirror)
        echo "Mirroring $HDMI_OUTPUT with $REFERENCE..."
        xrandr --output "$HDMI_OUTPUT" --auto --same-as "$REFERENCE"
        ;;
    *)
        echo -e "${RED}Unknown position: $POSITION${NC}"
        echo "Options: right, left, above, below, mirror"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Active monitors:${NC}"
xrandr --listmonitors
echo ""
