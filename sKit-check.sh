#!/bin/sh
#
#sKit-check.sh
#
#
#
# soundcheck's tuning kit - pCP - sKit-check.sh
# checks the tuning status 
# for RPi3/4/5 and related CM modules
#
# Latest Update: Jan-2026 (pCP11 compatibility patch)
# Original: Aug-07-2021
#
# CHANGELOG (pCP11 adaptation):
# - Added RPi5 detection via /proc/device-tree/model
# - Fixed vcgencmd measure_clock (use sysfs on RPi5)
# - Fixed tvservice (use DRM status on RPi5)
# - Added kernel version check
# - Fixed CPU clock expectations (2400MHz for RPi5)
# - Updated force_turbo check for RPi5
#
# Copyright © 2021 - Klaus Schulz
# All rights reserved
# 
# This program is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License 
# as published by the Free Software Foundation, 
# either version 3 of the License, or (at your option) 
# any later version.
#
# This program is distributed in the hope that it will be useful, 
# but WITHOUT ANY WARRANTY; without even the implied warranty 
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
# See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License 
# along with this program. 
#
# If not, see http://www.gnu.org/licenses
#
########################################################################
VERSION=1.5
sKit_VERSION=1.6

fname="${0##*/}"
opts="$@"
license_accept_flag=/mnt/mmcblk0p2/tce/.sKit-license-accepted.flag

###functions############################################################
colors() {

    RED='\033[0;31m'
    GREEN="\033[0;32m"
    YELLOW="\033[0;33m" 
    NC='\033[0m'
}


out() {

    echo -e "\tprogram aborted"
    echo -e "\t${RED}ERROR: $@ ${NC}"
    DONE
    exit 1
}


line() {

    echo -e "${RED}_______________________________________________________________${NC}\n"
}


checkroot() {

    (( EUID != 0 )) && out "root privileges required"
}


header() {

    line
    echo -e "\t      sKit - check ($VERSION)"
    echo -e "\t       (c) soundcheck"
    echo
    echo -e "\t      welcome $(id -un)@$(hostname)"
    line
}


DONE() {

    line
}


###################################
check_pcp() {

    if ! uname -a | grep -q -i pcp; then 
    
       out "No piCorePlayer system"
       
    fi
}


detect_rpi_model() {

    # Detect RPi model for hardware-specific checks
    if [ -f /proc/device-tree/model ]; then
        RPI_MODEL=$(cat /proc/device-tree/model 2>/dev/null)
        if echo "$RPI_MODEL" | grep -q "Raspberry Pi 5"; then
            IS_RPI5=1
        else
            IS_RPI5=0
        fi
    else
        IS_RPI5=0
    fi
}


license() {

	if [[ ! -f $license_accept_flag ]]; then

		line
		echo "
    soundcheck's tuning kit ($fname)
    
    Copyright © 2021 - Klaus Schulz (aka soundcheck)
    All rights reserved

    This program is free software: you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation,
    either version 3 of the License, or (at your option) 
    any later version.
    
    This program is distributed in the hope that it will be useful, 
    but WITHOUT ANY WARRANTY; without even the implied warranty 
    of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
    See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License 
    along with this program. 

    If not, see http://www.gnu.org/licenses
    "


		while true; do

			read -t 120 -r -p "    Confirm terms? (y/n)  : " yn
			case $yn in

				[Yy]* ) touch $license_accept_flag; break;;
				    * ) DONE;exit;;

			esac

		done
		clear
	fi
}


env_set() {

    TCE=/mnt/mmcblk0p2/tce 
    sKitbase=$TCE/sKit
    LOGDIR=$sKitbase/log
    LOG=$LOGDIR/$fname.log
    BOOT_DEV=/dev/mmcblk0p1 
    BOOT_MNT=/mnt/mmcblk0p1
    
    # RPi5 uses /boot/firmware, but symlink should exist
    # Check both locations
    if [ -f /boot/firmware/config.txt ]; then
        CONFIG=/boot/firmware/config.txt
        CMDLINE=/boot/firmware/cmdline.txt
    else
        CONFIG=$BOOT_MNT/config.txt
        CMDLINE=$BOOT_MNT/cmdline.txt
    fi
    
    pcpcfg=/usr/local/etc/pcp/pcp.cfg
    REPO_sKit="https://raw.githubusercontent.com/dugolub/sKit/dg-pCP11"
}


set_log() {

    echo >$LOG
}

GREEN() {
    echo -e "\t${GREEN}$@${NC}"
}

RED() {
    echo -e "\t${RED}$@${NC}"
}

YELLOW() {
    echo -e "\t${YELLOW}$@${NC}"
}


mount_boot() {

    if [[ ! -d $BOOT_MNT ]]; then 

        sudo mkdir -p $BOOT_MNT

    fi
    if grep -q "$BOOT_DEV" /proc/mounts; then
    
        sudo umount -f "$BOOT_DEV"

    fi
    sudo mount $BOOT_DEV $BOOT_MNT || out "mounting boot"
    sleep 1
}


check_leds() {

    echo -en "\tLEDs\t\t\t"
    grep -q -i "act_led_activelow=off" $CONFIG && GREEN "disabled" || RED "enabled" 

}


check_isolcpus() {

    echo -en "\tisolcpus\t\t"
    
    # Check for proper kernel 6.x syntax
    if grep -q -i 'isolcpus=[0-9].*domain.*managed' $CMDLINE; then
        GREEN "enabled (proper syntax)"
    elif grep -q -i 'isolcpus=[0-9]' $CMDLINE; then
        YELLOW "enabled (old syntax, may not work on kernel 6.x)"
    else
        RED "disabled"
    fi
}


check_internalaudio() {

    echo -en "\tinternal audio\t\t"
    grep -q -i "#dtparam=audio" $CONFIG && GREEN "disabled" || RED "enabled" 
}


check_hdmi() {

    echo -en "\thdmi\t\t\t"
    
    if [ "$IS_RPI5" = "1" ]; then
        # RPi5: tvservice doesn't exist, check DRM status
        if [ -d /sys/class/drm/card1-HDMI-A-1 ]; then
            status=$(cat /sys/class/drm/card1-HDMI-A-1/status 2>/dev/null || echo "unknown")
            [ "$status" = "disconnected" ] && GREEN "disabled" || YELLOW "enabled (DRM)"
        else
            YELLOW "N/A (no DRM device)"
        fi
    else
        # RPi3/4: tvservice works
        sudo tvservice -s 2>/dev/null | grep -q -i "off" && GREEN "disabled" || RED "enabled"
    fi

}


check_bluetooth() {

    echo -en "\tbluetooth\t\t"
    grep -q -i "dtoverlay=disable-bt" $CONFIG && GREEN "disabled" || RED "enabled" 

}


check_skitweaks() {

    echo -en "\tsKit-tweaks\t\t"
    grep -i "sKit-tweaks" $pcpcfg | grep -q '="%' $pcpcfg && RED "disabled" || GREEN "enabled" 
}


check_temperature() {

   if [ "$IS_RPI5" = "1" ]; then
       # RPi5: read from sysfs (in millidegrees)
       temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
       temp=$(echo "scale=1; $temp_raw / 1000" | bc)
   else
       # RPi3/4: vcgencmd works
       temp=$(sudo vcgencmd measure_temp 2>/dev/null | cut -f 2 -d "=" | cut -f 1 -d "'")
   fi
   
   echo -en "\tCPU temperature\t\t"
   if [[ "$(echo $temp'>'50.0 | bc -l)" == "0" ]]; then
        GREEN "$temp°C"
   elif [[ "$(echo $temp'>'55.0 | bc -l)" == "0" ]]; then
        YELLOW "$temp°C"
   else
        RED "$temp°C"
   fi
}


check_cpuclock() {

    echo -en "\tCPU clock\t\t"
    
    if [ "$IS_RPI5" = "1" ]; then
        # RPi5: vcgencmd measure_clock doesn't work, read from sysfs
        cpu_clock_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0)
        cpu_clock=$((cpu_clock_khz / 1000))
        expected_max=2400
    else
        # RPi3/4: vcgencmd works
        cpu_clock=$(( $(sudo vcgencmd measure_clock arm 2>/dev/null | cut -d '=' -f 2) / 1000000 ))
        expected_max=1500
    fi
    
    if [[ "$cpu_clock" -ge "$expected_max" ]]; then
        GREEN "${cpu_clock} MHz"
    else
        RED "${cpu_clock} MHz (expected: ${expected_max})"
    fi
}

check_governor() {

    echo -en "\tCPU governor\t\t"
    gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    if [[ "$gov" == "performance" ]]; then
        GREEN "$gov"
    else
        RED "$gov"
    fi
}


check_forcecpu() {

    gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    ftu="$(grep -i "^force_turbo=1" $CONFIG)"

    echo -en "\tforced CPU clock\t"
    if [[ -z "$ftu"  ]] && [[ "$gov" == "performance" ]]; then
       YELLOW "disabled"
    elif [[ ! -z "$ftu" ]]; then
       GREEN "enabled"
    else
       RED "disabled"
    fi
}



check_custom_squeezelite() {

    echo -en "\tcustom squeezelite\t"
    [[ -f /mnt/mmcblk0p2/tce/squeezelite-custom ]] && { GREEN "enabled"; CSL=1; } || RED "disabled" 
}


check_affinity_squeezelite() {

    echo -en "\t  c-s affinity main\t"
    grep "SQLAFFINITY" $pcpcfg | grep -q "1,2" && GREEN "OK" || RED "please check"
    echo -en "\t  c-s affinity output\t"
    grep "OTHER" $pcpcfg | grep -q "\-A" && GREEN "OK" || RED "please check"
}


check_rambuffer_squeezelite() {

    echo -en "\t  c-s ramplayback\t"
    RAMBUFFER=$(grep BUFFER_SIZE $pcpcfg | cut -f 2 -d ":" |sed 's/"//')

    [[ $RAMBUFFER -lt 100000 ]]     && RED "too low @$RAMBUFFER"
    [[ $RAMBUFFER -ge 100000 && $RAMBUFFER -lt 300000 ]] && YELLOW "not bad @$RAMBUFFER"
    [[ $RAMBUFFER -ge 300000 ]] && GREEN "OK"
}


check_alsa_params() {

    echo -en "\t  c-s alsa params\t"
    alsa_params="$(grep "ALSA_PARAMS"  $pcpcfg | cut -f 2 -d '"')"
    if [[ "$alsa_params" == "::::" ]]; then
        RED "not set"
    elif [[ "$alsa_params" == "160:4::1:" || "$alsa_params" == "65536:4::1:" ]]; then 
        GREEN "OK"
    else 
        YELLOW "please check values"
    fi
}


check_priority() {

    echo -en "\t  c-s output priority\t"
    PRIORITY=$(grep "PRIORITY" $pcpcfg | cut -f 2 -d '"' | sed 's/"//')
    if [[ -z $PRIORITY ]]; then
        RED "not set"
    elif [[ $PRIORITY -lt 45 && $PRIORITY -gt 50 ]]; then 
        RED "please check" 
    else
        GREEN "OK"
    fi   
}


check_netif() {

    echo -en "\tnetwork interface\t"
    netif=$(route | grep default | awk '{print $8}')
    if [[ "$netif" == "wlan0" ]]; then
        YELLOW "$netif"
    else
        GREEN "$netif"
    fi
}


check_sKitrev() {

    echo
    echo -e "\tsKit revison\t\t\t$sKit_VERSION"
    echo -en "\tsKit status\t\t"
    skm="sKit-manager.sh"

    tskm="/tmp/$skm"
    lskm="$sKitbase/bin/$skm"

    wget -q "$REPO_sKit/$skm" -O "$tskm" 

    sKit_reporev=$(grep "^sKit_VER" $tskm | cut -f 2 -d "=")
    sKit_actrev=$(grep "^sKit_VER" $lskm | cut -f 2 -d "=")

    if [[ "$sKit_actrev" == "$sKit_reporev" ]]; then 
		GREEN "up-2-date" 
	else	
		RED "update available"
	fi
	
    echo
}


check_bootloader() {

   if [ "$IS_RPI5" = "1" ]; then
       # RPi5: bootloader version works
       act_bl=$(sudo vcgencmd bootloader_version 2>/dev/null | head -1)
   else
       act_bl=$(sudo vcgencmd bootloader_version 2>/dev/null | head -1)
   fi
}


load_rpi_vc() {

    echo -en "\tloading RPi utils\t\t"
    # rpi-vc package may not fully support RPi5
    if tce-load -sil rpi-vc >>$LOG 2>&1; then
        echo "OK" >>$LOG
    else
        echo "WARNING: rpi-vc load failed (expected on RPi5)" >>$LOG
    fi
} 


print_pcp_version() {

    pcpvers=$(grep "PCPVERS" /usr/local/etc/pcp/pcpversion.cfg | cut -f 2 -d '"' | cut -f 2 -d " ")
    echo
    echo -e "\tpCP version\t\t\t$pcpvers"
}


check_kernel() {

    kern_ver=$(uname -r)
    echo -e "\tKernel version\t\t\t$kern_ver"
    
    # Warn if not expected kernel for pCP11
    kern_maj=$(echo $kern_ver | cut -d'.' -f1)
    if [ "$kern_maj" -lt "6" ]; then
        echo -en "\tKernel compatibility\t"
        RED "outdated for pCP11 (expected 6.x)"
    fi
}


###main#######################################
colors
license

header

check_pcp
detect_rpi_model
env_set
set_log
load_rpi_vc
mount_boot

print_pcp_version
check_kernel
check_sKitrev

check_temperature
check_governor
check_cpuclock
check_forcecpu
check_isolcpus
check_hdmi
check_bluetooth
check_internalaudio
check_netif

check_leds
check_skitweaks
check_custom_squeezelite
if [[ "$CSL" == "1" ]]; then 
    check_priority
    check_affinity_squeezelite
    check_rambuffer_squeezelite
    check_alsa_params
fi

check_bootloader

DONE
exit 0
##############################################
