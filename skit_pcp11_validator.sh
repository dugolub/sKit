#!/bin/bash
#
# sKit-pcp11-validator.sh
#
# Validation script for sKit compatibility with pCP11 + RPi5
# Run this BEFORE installing sKit to check for potential issues
#
# Usage: sudo sh sKit-pcp11-validator.sh
#
# Copyright © 2026 - pCP11 compatibility check
# Based on soundcheck's sKit
#
########################################################################

VERSION="1.0"

# Colors
RED='\033[0;31m'
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NC='\033[0m'

line() {
    echo -e "${RED}_______________________________________________________________${NC}\n"
}

header() {
    line
    echo -e "\t${GREEN}sKit pCP11/RPi5 Compatibility Validator ($VERSION)${NC}"
    line
}

check_item() {
    local item="$1"
    local status="$2"
    local message="$3"
    
    printf "\t%-35s" "$item:"
    
    case "$status" in
        "OK")
            echo -e "${GREEN}✓ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠ $message${NC}"
            ;;
        "FAIL")
            echo -e "${RED}✗ $message${NC}"
            CRITICAL_FAIL=1
            ;;
    esac
}

###############################################
# Main validation
###############################################

header
CRITICAL_FAIL=0

# 1. Check if piCorePlayer
echo -e "\t${YELLOW}[1] System Check${NC}"
if uname -a | grep -q -i pcp; then
    check_item "piCorePlayer detected" "OK" "Yes"
else
    check_item "piCorePlayer detected" "FAIL" "Not a pCP system"
fi

# 2. Kernel version
echo
echo -e "\t${YELLOW}[2] Kernel Version${NC}"
KERN=$(uname -r)
KERN_MAJ=$(echo $KERN | cut -d'.' -f1)
KERN_MIN=$(echo $KERN | cut -d'.' -f2)

check_item "Kernel version" "OK" "$KERN"

if [ "$KERN_MAJ" -ge "6" ]; then
    check_item "Kernel 6.x compatibility" "OK" "Compatible with pCP11"
else
    check_item "Kernel 6.x compatibility" "WARNING" "Expected kernel 6.x for pCP11"
fi

# 3. TinyCore version
echo
echo -e "\t${YELLOW}[3] TinyCore Version${NC}"
if [ -f /etc/os-release ]; then
    TC_VER=$(grep "VERSION_ID" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    if [ -n "$TC_VER" ]; then
        check_item "TinyCore version" "OK" "$TC_VER"
        
        TC_MAJ=$(echo $TC_VER | cut -d'.' -f1)
        if [ "$TC_MAJ" -ge "16" ]; then
            check_item "TC 16.x compatibility" "OK" "Compatible with pCP11"
        else
            check_item "TC 16.x compatibility" "WARNING" "Expected TC 16.x for pCP11 (found $TC_VER)"
        fi
    else
        check_item "TinyCore version" "WARNING" "Could not detect version"
    fi
else
    check_item "TinyCore version" "WARNING" "/etc/os-release not found"
fi

# 4. pCP version
echo
echo -e "\t${YELLOW}[4] piCorePlayer Version${NC}"
if [ -f /usr/local/etc/pcp/pcpversion.cfg ]; then
    PCP_VER=$(grep "PCPVERS" /usr/local/etc/pcp/pcpversion.cfg | cut -d'"' -f2)
    check_item "pCP version" "OK" "$PCP_VER"
    
    PCP_MAJ=$(echo $PCP_VER | cut -d'.' -f1)
    if [ "$PCP_MAJ" -ge "11" ]; then
        check_item "pCP 11+ detected" "OK" "Yes"
    else
        check_item "pCP 11+ detected" "WARNING" "pCP $PCP_MAJ detected (expected 11+)"
    fi
else
    check_item "pCP version" "FAIL" "pcpversion.cfg not found"
fi

# 5. TCZ Repository availability
echo
echo -e "\t${YELLOW}[5] TCZ Repository Check${NC}"
ARCH=$(uname -m)
TC_VER_SHORT="16.x"
REPO="https://repo.picoreplayer.org/repo/${TC_VER_SHORT}/$ARCH/tcz"

check_item "Architecture" "OK" "$ARCH"
check_item "Expected repo path" "OK" "$REPO"

# Test connectivity
if wget -q --spider --timeout=10 "$REPO/gcc.tcz" 2>/dev/null; then
    check_item "Repository accessible" "OK" "Can reach $REPO"
else
    check_item "Repository accessible" "WARNING" "Cannot reach repo (network issue or wrong TC version)"
fi

# 6. Kernel headers package
echo
echo -e "\t${YELLOW}[6] Kernel Headers Package${NC}"
KERN_PKG="linux-${KERN_MAJ}.${KERN_MIN}.y_api_headers"
check_item "Expected headers package" "OK" "$KERN_PKG"

if wget -q --spider --timeout=10 "$REPO/${KERN_PKG}.tcz" 2>/dev/null; then
    check_item "Headers package exists" "OK" "${KERN_PKG}.tcz found in repo"
else
    check_item "Headers package exists" "FAIL" "${KERN_PKG}.tcz NOT FOUND - build will fail"
fi

# 7. RPi Model Detection
echo
echo -e "\t${YELLOW}[7] Raspberry Pi Model${NC}"
if [ -f /proc/device-tree/model ]; then
    RPI_MODEL=$(cat /proc/device-tree/model 2>/dev/null)
    check_item "RPi model" "OK" "$RPI_MODEL"
    
    if echo "$RPI_MODEL" | grep -q "Raspberry Pi 5"; then
        IS_RPI5=1
        check_item "RPi5 detected" "OK" "Yes - using RPi5-specific checks"
    else
        IS_RPI5=0
        check_item "RPi5 detected" "OK" "No - RPi3/4 detected"
    fi
else
    check_item "RPi model" "WARNING" "Could not detect model"
    IS_RPI5=0
fi

# 8. Boot partition layout
echo
echo -e "\t${YELLOW}[8] Boot Partition Layout${NC}"
if [ -f /boot/firmware/config.txt ]; then
    check_item "Boot path" "OK" "/boot/firmware/config.txt (RPi5 layout)"
    BOOT_PATH="/boot/firmware"
elif [ -f /boot/config.txt ]; then
    check_item "Boot path" "OK" "/boot/config.txt (legacy layout)"
    BOOT_PATH="/boot"
else
    check_item "Boot path" "FAIL" "config.txt not found"
    BOOT_PATH=""
fi

# 9. vcgencmd availability (RPi5 check)
echo
echo -e "\t${YELLOW}[9] vcgencmd Tools${NC}"
if [ "$IS_RPI5" = "1" ]; then
    # RPi5: measure_clock shouldn't work
    if vcgencmd measure_clock arm 2>/dev/null | grep -q "frequency"; then
        check_item "vcgencmd measure_clock" "WARNING" "Works (unexpected on RPi5)"
    else
        check_item "vcgencmd measure_clock" "OK" "Not supported (expected on RPi5)"
    fi
    
    # Check sysfs fallback
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
        check_item "sysfs CPU frequency" "OK" "$((FREQ / 1000)) MHz"
    else
        check_item "sysfs CPU frequency" "FAIL" "sysfs path not available"
    fi
else
    # RPi3/4: vcgencmd should work
    if vcgencmd measure_clock arm 2>/dev/null | grep -q "frequency"; then
        check_item "vcgencmd measure_clock" "OK" "Working"
    else
        check_item "vcgencmd measure_clock" "WARNING" "Not working"
    fi
fi

# 10. tvservice (RPi5 check)
echo
echo -e "\t${YELLOW}[10] tvservice / HDMI${NC}"
if [ "$IS_RPI5" = "1" ]; then
    if command -v tvservice >/dev/null 2>&1; then
        check_item "tvservice" "WARNING" "Exists but deprecated on RPi5"
    else
        check_item "tvservice" "OK" "Not present (expected on RPi5)"
    fi
    
    # Check DRM fallback
    if [ -d /sys/class/drm/card1-HDMI-A-1 ]; then
        check_item "DRM HDMI interface" "OK" "Available as fallback"
    else
        check_item "DRM HDMI interface" "WARNING" "Not found"
    fi
else
    if command -v tvservice >/dev/null 2>&1; then
        check_item "tvservice" "OK" "Available"
    else
        check_item "tvservice" "WARNING" "Not found"
    fi
fi

# 11. isolcpus check
echo
echo -e "\t${YELLOW}[11] CPU Isolation Check${NC}"
CMDLINE=$(cat /proc/cmdline 2>/dev/null)
if echo "$CMDLINE" | grep -q "isolcpus=[0-9]"; then
    ISOL=$(echo "$CMDLINE" | grep -o "isolcpus=[^ ]*")
    check_item "Current isolcpus" "OK" "$ISOL"
    
    if echo "$ISOL" | grep -q "domain.*managed"; then
        check_item "isolcpus syntax" "OK" "Correct for kernel 6.x (has domain,managed)"
    else
        check_item "isolcpus syntax" "WARNING" "Old syntax - may be ignored by kernel 6.x"
    fi
else
    check_item "Current isolcpus" "OK" "Not configured"
fi

# 12. Disk space
echo
echo -e "\t${YELLOW}[12] Disk Space${NC}"
if [ -d /mnt/mmcblk0p2 ]; then
    SPACE=$(/bin/df -m /mnt/mmcblk0p2 2>/dev/null | tail -1 | awk '{print $4}')
    TOTAL=$(/bin/df -m /mnt/mmcblk0p2 2>/dev/null | tail -1 | awk '{print $2}')
    
    check_item "Available space" "OK" "${SPACE}MB / ${TOTAL}MB"
    
    if [ "$SPACE" -lt "100" ]; then
        check_item "Space requirement" "FAIL" "Need at least 100MB free (have ${SPACE}MB)"
    else
        check_item "Space requirement" "OK" "Sufficient space for build"
    fi
else
    check_item "Partition /mnt/mmcblk0p2" "FAIL" "Not accessible"
fi

# 13. Memory check
echo
echo -e "\t${YELLOW}[13] Memory Check${NC}"
MEM_TOTAL=$(free -m | grep "^Mem:" | awk '{print $2}')
MEM_FREE=$(free -m | grep "^Mem:" | awk '{print $4}')

check_item "Total RAM" "OK" "${MEM_TOTAL}MB"
check_item "Free RAM" "OK" "${MEM_FREE}MB"

if [ "$MEM_TOTAL" -lt "2000" ]; then
    check_item "RAM requirement" "WARNING" "Low RAM - build may be slow or fail"
elif [ "$MEM_TOTAL" -ge "4000" ]; then
    check_item "RAM requirement" "OK" "Plenty of RAM for build"
else
    check_item "RAM requirement" "OK" "Adequate RAM for build"
fi

# Summary
echo
line
echo -e "\t${YELLOW}[Summary]${NC}"
echo

if [ "$CRITICAL_FAIL" = "1" ]; then
    echo -e "\t${RED}✗ CRITICAL ISSUES DETECTED${NC}"
    echo -e "\t${RED}  sKit installation will likely FAIL${NC}"
    echo -e "\t${RED}  Fix the issues marked with ✗ above${NC}"
    echo
    EXIT_CODE=1
else
    echo -e "\t${GREEN}✓ No critical issues detected${NC}"
    echo -e "\t${GREEN}  sKit should install successfully${NC}"
    
    if grep -q "WARNING" /tmp/skit-validator-$$ 2>/dev/null; then
        echo
        echo -e "\t${YELLOW}⚠ Some warnings were found${NC}"
        echo -e "\t${YELLOW}  Review items marked with ⚠ above${NC}"
    fi
    echo
    EXIT_CODE=0
fi

line

exit $EXIT_CODE
