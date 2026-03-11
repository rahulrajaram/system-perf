#!/bin/bash

# kwin_wayland GPU Configuration Fix Script
# Diagnoses hybrid GPU issues and tests single-GPU configurations

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== kwin_wayland GPU Configuration Tool ===${NC}"
echo ""

#------------------------------------------------------------------------------
# Detect GPUs
#------------------------------------------------------------------------------
echo -e "${CYAN}[1/4] Detecting GPUs...${NC}"

declare -A GPU_NAMES
declare -A GPU_VENDORS

for card in /dev/dri/card*; do
    cardname=$(basename "$card")
    vendor=$(cat /sys/class/drm/$cardname/device/vendor 2>/dev/null || echo "unknown")

    case $vendor in
        0x8086) GPU_NAMES[$card]="Intel"; GPU_VENDORS[$card]="intel" ;;
        0x10de) GPU_NAMES[$card]="NVIDIA"; GPU_VENDORS[$card]="nvidia" ;;
        0x1002) GPU_NAMES[$card]="AMD"; GPU_VENDORS[$card]="amd" ;;
        *) GPU_NAMES[$card]="Unknown ($vendor)"; GPU_VENDORS[$card]="unknown" ;;
    esac

    echo "  $card: ${GPU_NAMES[$card]}"
done

echo ""

#------------------------------------------------------------------------------
# Check current kwin status
#------------------------------------------------------------------------------
echo -e "${CYAN}[2/4] Current kwin_wayland status...${NC}"

KWIN_PID=$(pgrep -x kwin_wayland 2>/dev/null || true)
if [ -z "$KWIN_PID" ]; then
    echo -e "${YELLOW}  kwin_wayland is not running${NC}"
else
    echo "  PID: $KWIN_PID"

    # CPU usage
    CPU=$(ps -p $KWIN_PID -o %cpu= 2>/dev/null | tr -d ' ')
    echo "  CPU: ${CPU}%"

    # Check which GPU FDs are open (needs root)
    if [ "$EUID" -eq 0 ]; then
        echo "  Open GPU devices:"
        for fd in /proc/$KWIN_PID/fd/*; do
            target=$(readlink "$fd" 2>/dev/null || true)
            if echo "$target" | grep -qE "card|render"; then
                echo "    fd $(basename $fd) -> $target"
            fi
        done
    else
        echo -e "  ${YELLOW}(Run as root to see open GPU file descriptors)${NC}"
    fi

    # Check current environment
    echo "  Current KWIN_DRM_DEVICES: ${KWIN_DRM_DEVICES:-<not set>}"
fi

echo ""

#------------------------------------------------------------------------------
# Show menu
#------------------------------------------------------------------------------
echo -e "${CYAN}[3/4] Configuration Options${NC}"
echo ""
echo "Choose a GPU configuration to test:"
echo ""

i=1
declare -A OPTIONS

for card in /dev/dri/card*; do
    echo "  $i) ${GPU_NAMES[$card]} only ($card)"
    OPTIONS[$i]="$card"
    ((i++))
done

# Add render nodes
for render in /dev/dri/renderD*; do
    if [ -e "$render" ]; then
        # Find corresponding card
        rendernum=$(basename "$render" | sed 's/renderD//')
        cardnum=$((rendernum - 128))
        card="/dev/dri/card$cardnum"
        if [ -n "${GPU_NAMES[$card]}" ]; then
            echo "  $i) ${GPU_NAMES[$card]} render node only ($render)"
            OPTIONS[$i]="$render"
            ((i++))
        fi
    fi
done

echo "  $i) Both GPUs (default - no override)"
OPTIONS[$i]="default"
((i++))

echo "  $i) Show current kwin environment"
OPTIONS[$i]="show_env"
((i++))

echo "  $i) Generate systemd override file"
OPTIONS[$i]="systemd"
((i++))

echo "  $i) Exit"
OPTIONS[$i]="exit"

echo ""
read -p "Enter choice [1-$i]: " choice

#------------------------------------------------------------------------------
# Execute choice
#------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}[4/4] Applying configuration...${NC}"
echo ""

case ${OPTIONS[$choice]} in
    "exit")
        echo "Exiting."
        exit 0
        ;;

    "show_env")
        echo "Current kwin_wayland environment:"
        if [ -n "$KWIN_PID" ]; then
            if [ "$EUID" -eq 0 ]; then
                cat /proc/$KWIN_PID/environ 2>/dev/null | tr '\0' '\n' | grep -E "KWIN|DRM|DRI|GPU|DISPLAY|WAYLAND" || echo "(no relevant vars found)"
            else
                echo -e "${YELLOW}Run as root to see process environment${NC}"
            fi
        fi
        exit 0
        ;;

    "systemd")
        echo "Creating systemd user override for plasma-kwin_wayland.service..."
        echo ""

        OVERRIDE_DIR="$HOME/.config/systemd/user/plasma-kwin_wayland.service.d"
        mkdir -p "$OVERRIDE_DIR"

        echo "Select GPU for systemd override:"
        j=1
        for card in /dev/dri/card*; do
            echo "  $j) ${GPU_NAMES[$card]} ($card)"
            ((j++))
        done
        read -p "Enter choice: " gpu_choice

        selected_card=$(ls /dev/dri/card* | sed -n "${gpu_choice}p")

        cat > "$OVERRIDE_DIR/gpu-override.conf" << EOF
[Service]
Environment="KWIN_DRM_DEVICES=$selected_card"
EOF

        echo -e "${GREEN}Created: $OVERRIDE_DIR/gpu-override.conf${NC}"
        echo ""
        cat "$OVERRIDE_DIR/gpu-override.conf"
        echo ""
        echo "To apply, run:"
        echo "  systemctl --user daemon-reload"
        echo "  systemctl --user restart plasma-kwin_wayland.service"
        echo ""
        echo "Or log out and back in."
        exit 0
        ;;

    "default")
        echo "Resetting to default (both GPUs)..."
        unset KWIN_DRM_DEVICES

        # Remove systemd override if exists
        OVERRIDE_FILE="$HOME/.config/systemd/user/plasma-kwin_wayland.service.d/gpu-override.conf"
        if [ -f "$OVERRIDE_FILE" ]; then
            echo "Removing systemd override: $OVERRIDE_FILE"
            rm -f "$OVERRIDE_FILE"
            echo "Run: systemctl --user daemon-reload"
        fi

        echo ""
        echo "To restart kwin with both GPUs, run:"
        echo "  kwin_wayland --replace &"
        exit 0
        ;;

    /dev/dri/*)
        SELECTED_DEVICE="${OPTIONS[$choice]}"
        echo "Testing with: $SELECTED_DEVICE"
        echo ""

        # Create test script
        TEST_SCRIPT="/tmp/test_kwin_gpu.sh"
        cat > "$TEST_SCRIPT" << EOF
#!/bin/bash
export KWIN_DRM_DEVICES="$SELECTED_DEVICE"
echo "Starting kwin_wayland with KWIN_DRM_DEVICES=$SELECTED_DEVICE"
echo ""
echo "If display breaks, switch to TTY (Ctrl+Alt+F2) and run:"
echo "  pkill kwin_wayland"
echo "  KWIN_DRM_DEVICES=/dev/dri/card0 kwin_wayland --replace &"
echo ""
echo "Starting in 3 seconds... (Ctrl+C to cancel)"
sleep 3
kwin_wayland --replace &
KWIN_PID=\$!
sleep 5
echo ""
echo "New kwin_wayland PID: \$KWIN_PID"
echo "CPU usage:"
ps -p \$KWIN_PID -o %cpu= 2>/dev/null || echo "(process not found)"
EOF
        chmod +x "$TEST_SCRIPT"

        echo -e "${YELLOW}WARNING: This will restart your compositor!${NC}"
        echo "Your screen may flicker or go black temporarily."
        echo ""
        echo "Test script created: $TEST_SCRIPT"
        echo ""
        read -p "Run now? [y/N]: " confirm

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo ""
            echo "Running test..."
            bash "$TEST_SCRIPT"

            # Wait and check CPU
            sleep 10
            NEW_PID=$(pgrep -x kwin_wayland 2>/dev/null || true)
            if [ -n "$NEW_PID" ]; then
                NEW_CPU=$(ps -p $NEW_PID -o %cpu= 2>/dev/null | tr -d ' ')
                echo ""
                echo -e "${GREEN}Results:${NC}"
                echo "  PID: $NEW_PID"
                echo "  CPU: ${NEW_CPU}%"

                if (( $(echo "$NEW_CPU < 20" | bc -l 2>/dev/null || echo 0) )); then
                    echo -e "  ${GREEN}SUCCESS: CPU usage is now reasonable!${NC}"
                    echo ""
                    echo "To make permanent, run:"
                    echo "  $0"
                    echo "  Then choose 'Generate systemd override file'"
                else
                    echo -e "  ${YELLOW}CPU still high. Try a different GPU.${NC}"
                fi
            fi
        else
            echo ""
            echo "To run manually:"
            echo "  KWIN_DRM_DEVICES=$SELECTED_DEVICE kwin_wayland --replace &"
        fi
        ;;

    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Done.${NC}"
