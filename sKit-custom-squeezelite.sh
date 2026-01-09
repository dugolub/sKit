#!/bin/sh
#
#sKit-custom-squeezelite.sh
#
# soundcheck's tuning kit - pCP - sKit-custom-squeezlite.sh
# custom squeezelite binary build tool for piCorePlayer
# supporting RPi3/4/5 and related CM modules
#
# Latest Update: Jan-2026 (pCP11 compatibility patch)
# Original: Nov-18-2021
#
# CHANGELOG (pCP11 adaptation):
# - Dynamic TinyCore version detection (16.x for pCP11)
# - Dynamic kernel headers detection (6.12.y for pCP11)
# - Dynamic extensions list generation
# - Fixed isolcpus syntax for kernel 6.x (domain,managed)
# - Added RPi5 boot path detection
# - Improved error handling for TC version mismatch
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
VERSION="1.5-pcp11"
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

    echo
    echo -e "\tprogram aborted:"
    echo -e "\t${RED}ERROR: $@${NC}"
    DONE
    exit 1
}


line() {

    printf "${RED}%*s${NC}\n" 80 "" | tr ' ' _
    echo
}



checkroot() {

    (( EUID != 0 )) && out "root privileges required"
}


header() {

    line
    echo -e "\t   sKit - custom squeezelite builder ($VERSION)"
    echo -e "\t            (c) soundcheck"
    echo
    echo -e "\t           welcome $(id -un)@$(hostname)"
    line
}


DONE() {

    line
    sync
}


countdown() {

    counter=$1
    while [[ "$counter" -gt 0 ]]; do


        echo -ne -e "\t>> $counter \r"
        let counter--
        sleep 1

    done
    echo -e "\t>> 0"
    line
}


reboot_system() {

   if [[ "$REBOOT" == "true" ]]; then

      echo -e "\trebooting system in"
      countdown 10
      sudo reboot
      exit 1

   fi
}


############################################
check_pcp() {

    if ! uname -a | grep -q -i pcp; then 
    
        out "No piCorePlayer system"
       
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


generate_extensions_list() {

    # Core build packages (version-neutral names)
    local CORE_PKGS="
binutils
bison
bzip2-lib
curl
diffutils
e2fsprogs_base-dev
expat2
file
findutils
flex
gamin
gawk
gcc_base-dev
gcc_libs-dev
gcc_libs
gcc
git
glib2
glibc_add_lib
glibc_apps
glibc_base-dev
glibc_gconv
gmp
grep
isl
libasound-dev
libelf
libffi_base-dev
libzstd
m4
make
mpc
mpfr
patch
pcp-libalac-dev
pcp-libfaad2-dev
pcp-libflac-dev
pcp-libmad-dev
pcp-libmpg123-dev
pcp-libogg-dev
pcp-libsoxr-dev
pcp-libvorbis-dev
pcre
pkg-config
sed
util-linux_base-dev
zlib_base-dev
$KERNEL_PKG"

    # Generate extensions list - only mandatory files
    # .dep, .tree, .dep.pcp are optional and may not exist in repo
    EXTENSIONS=""
    for pkg in $CORE_PKGS; do
        EXTENSIONS="$EXTENSIONS
${pkg}.tcz
${pkg}.tcz.md5.txt"
    done
    
    # Load order (only .tcz basenames)
    # IMPORTANT: Order matters - dependencies must be loaded first
    EXTENSIONS_LOAD="libzstd
gmp
mpfr
mpc
isl
gcc_libs
gcc_base-dev
gcc_libs-dev
glibc_base-dev
glibc_add_lib
glibc_apps
glibc_gconv
$KERNEL_PKG
binutils
make
sed
grep
bison
flex
m4
patch
gawk
file
findutils
diffutils
git
libasound-dev
pcp-libogg-dev
pcp-libflac-dev
pcp-libvorbis-dev
pcp-libmad-dev
pcp-libmpg123-dev
pcp-libalac-dev
pcp-libfaad2-dev
pcp-libsoxr-dev
gcc"
}


env_set() {

    TCE=/mnt/mmcblk0p2/tce 
    TCEO=$TCE/optional
    ONB=$TCE/onboot.lst
    sKitbase=$TCE/sKit
    LOGDIR=$sKitbase/log
    LOG=$LOGDIR/$fname-$(date +%d%b%Y-%H%M).log
    DOWNLOAD_DIR="/tmp/ext"
    TARGET_DIR="$TCEO"
    pcpcfg=/usr/local/etc/pcp/pcp.cfg
    BOOT_MNT=/mnt/mmcblk0p1
    BOOT_DEV=/dev/mmcblk0p1
    ARCH="$(uname -m)"
    
    # Detect TinyCore version from pCP
    if [ -f /usr/local/etc/pcp/pcpversion.cfg ]; then
        PCP_MAJOR=$(grep "PCPVERS" /usr/local/etc/pcp/pcpversion.cfg | cut -d'"' -f2 | cut -d'.' -f1)
        
        # pCP version to TinyCore mapping
        case "$PCP_MAJOR" in
            11|12) TC_VER="16.x" ;;  # pCP 11+ = TC16
            9|10)  TC_VER="14.x" ;;
            8)     TC_VER="13.x" ;;
            *)     TC_VER="16.x" ;;  # default to latest
        esac
    else
        # Fallback: detect from kernel version
        KERN_MAJ=$(uname -r | cut -d'.' -f1)
        if [ "$KERN_MAJ" -ge "6" ]; then
            TC_VER="16.x"
        else
            TC_VER="13.x"
        fi
    fi
    
    SITE1="https://repo.picoreplayer.org"
    REPO1="${SITE1}/repo/${TC_VER}/$ARCH/tcz"
    SITE2="http://picoreplayer.sourceforge.net"
    REPO2="${SITE2}/tcz_repo/${TC_VER}/$ARCH/tcz"
    
    # Squeezelite repository
    # NOTE: Original klslz/squeezelite may be unavailable
    # Fallback to official ralph-irving squeezelite
    REPO_SL_PRIMARY="https://github.com/klslz/squeezelite.git"
    REPO_SL_FALLBACK="https://github.com/ralph-irving/squeezelite.git"
    REPO_SL="$REPO_SL_PRIMARY"
    
    EXT_BA="sKit-extensions-backup.tar.gz"
    
    # Detect kernel API headers package
    KERNEL_VER=$(uname -r | cut -d'.' -f1-2)  # e.g. 6.12
    KERNEL_PKG="linux-${KERNEL_VER}.y_api_headers"
    
    # Generate extensions list after KERNEL_PKG is defined
    generate_extensions_list

    BASE=/tmp/squeezelite
    ISOLCPUS="3"

	test -d "$DOWNLOAD_DIR" || mkdir -p "$DOWNLOAD_DIR"
	rm ${DOWNLOAD_DIR}/*tcz* 2>/dev/null
}


set_log() {

    PCP_REV="$(grep -R "piCorePlayer" /var/tmp/footer.html | awk '{print $2}')"
    ARCH="$(uname -m)"
    MEMORY="$(free -m | grep Mem)"
    KERN_VER="$(uname -r)"
    echo -e "\tsetting up log"
    echo >$LOG
    echo "*** sKit-custom-squeezelite: $VERSION" >>$LOG
    echo "*** pCP version: $PCP_REV" >>$LOG
    echo "*** TinyCore: $TC_VER" >>$LOG
    echo "*** Kernel: $KERN_VER" >>$LOG
    echo "*** Kernel headers package: $KERNEL_PKG" >>$LOG
    echo "*** Arch: $ARCH" >>$LOG
    echo "*** $MEMORY" >>$LOG 
    echo "**************************************************************" >>$LOG
    echo >>$LOG
}


save_config() {

    sudo filetool.sh -b >/dev/null
}


select_ext_repo() {

    echo -e "\tselect repository"
    echo
    echo -e "\t   1 = pCP master  (default)"
    echo -e "\t   2 = pCP mirror"
    echo
    read -t 15 -r -p "	   ?  " x
    x=${x:-1}
    echo

    case "$x" in
    
        1) REPO=$REPO1 ; TIMEOUT=400;;
        2) REPO=$REPO2 ; TIMEOUT=600;;
        *) REPO=$REPO1 ; TIMEOUT=400;;
 
    esac
    
    echo -e "\tUsing repository: $REPO"
    echo -e "\tTinyCore version: $TC_VER"
    echo -e "\tKernel headers: $KERNEL_PKG"
}


check_space() {

    space=$(/bin/df -m /mnt/mmcblk0p2 | tail -1 | awk '{print $4}')
    total=$(/bin/df -m /mnt/mmcblk0p2 | tail -1 | awk '{print $2}')

    echo -e "\tverifying space requirements"
    if [[ "$space" -lt "100" ]] && [[ ! -f "$TCEO/compiletc.tcz" ]]; then

        out "Not enough space (${space} of ${total}MB) on device, add at least 100MB!"

    fi
}


backup_extensions() {

    if [[ ! -f $sKitbase/$EXT_BA ]]; then

        echo -e "\tbacking up pre-installation extensions"
        cd $TCE
        tar czf $EXT_BA onboot.lst ./optional
        cp -f $EXT_BA $sKitbase

    fi
}


menu() {

    echo
    echo -e "\tselect squeezelite variant"
    echo
    echo -e "\t  1  = standard   - minimal"
    echo -e "\t  2  = standard   - DSD & SRC"
    echo -e "\t  3  = soundcheck - minimal (default)"
    echo -e "\t  4  = soundcheck - DSD & SRC"
    echo -e "\t  5  = soundcheck - DSD & SRC (MP)"
    echo
    echo -e "\t  6  = remove custom installation"
    echo -e "\t  *  = cancel"
    echo
    read -t 20 -r -p "	  ? : " x
    x=${x:-3}
    echo
    line

    clear
    header

    case $x in
 
      1)
        VARIANT="standard - minimal"
        VID="sKit-stmi"
        INSTALL master minimal
        ;;
      2)
        VARIANT="standard - DSD & SRC"
        VID="sKit-stds"
        INSTALL master dsdsrc
        ;;
      3)
        VARIANT="soundcheck - minimal"
        VID="sKit-scmi"
        INSTALL squeezelite-sc minimal
        ;;
      4)
        VARIANT="soundcheck - DSD & SRC"
        VID="sKit-scds"
        INSTALL squeezelite-sc dsdsrc
        ;;
      5)
        VARIANT="soundcheck - DSD & SRC (MultiProcessor)"
        VID="sKit-scdsm"
        INSTALL squeezelite-sc dsdsrc-mp
        ;;
      6)
        REMOVE
        ;;
      *)
        echo -e "\tcanceled"
        REBOOT=false
       ;;

    esac
}


download_extensions() {


    echo -e "\textensions download"
    echo
    echo -e "\t  repo: $REPO"
    echo
    start=$(date +%s)

	test -f /tmp/skit-dl.failed && rm /tmp/skit-dl.failed
	touch   /tmp/skit-dl.failed

	for ex in $EXTENSIONS; do

		if [[ ! -f $TARGET_DIR/$ex ]]; then 
			if [[ ! -f $DOWNLOAD_DIR/$ex ]]; then

				printf "\t%-18s%-38s" "downloading:" "$ex"

				DOWNLOAD_INITIATED=true 

				wget -P "$DOWNLOAD_DIR" ${REPO}/$ex >>$LOG 2>&1

				if [ $? -eq 0 ]; then

					stat="DOWNLOADED"
					DOWNLOAD_SUCCESS=true

				else
					# Only fail on critical files (.tcz and .md5.txt)
					# Optional files (.dep, .tree, .info) can be missing
					if [[ "$ex" == *.tcz ]] || [[ "$ex" == *.md5.txt ]]; then
						stat="FAILED"
						echo "$ex" >> /tmp/skit-dl.failed
					else
						stat="SKIPPED"
					fi
				fi

				if [[ "$stat" == "DOWNLOADED" ]]; then
					printf "${GREEN}%-15s${NC}\n" "$stat"
				elif [[ "$stat" == "SKIPPED" ]]; then
					printf "${YELLOW}%-15s${NC}\n" "$stat"
				else
					printf "${RED}%-15s${NC}\n" "$stat"
				fi

			fi
		fi


	done

    end=$(date +%s)
    total=$((end-start))
    duration=$(printf '%dm:%ds\n' $(($total%3600/60)) $(($total%60)))

	if [[ "$DOWNLOAD_INITIATED" == "true" ]]; then

			echo
			echo -e "\tdownload-duration: $duration"

	else

			echo
			echo -e "\tall required extentions already installed"

	fi
}


verify_extensions() {

	echo -e "\tverifiying extensions download"

	for i in 1 2 3 4; do

        if [[ -s "/tmp/skit-dl.failed" ]]; then

            echo
            echo -e "${RED}\tERROR: extensions download (partially) failed >> ${YELLOW}${i}. RETRY ${NC}"
            echo
            sleep 5
            download_extensions

        fi

	done

	if [[ -s "/tmp/skit-dl.failed" ]]; then

		echo -e "\t${RED}ERROR:   serious extensions download issue encountered${NC}"
		echo -e "\t${RED}         so far nothing has been changed${NC}"
		echo -e "\t${RED}         try later or choose different repo after reboot${NC}"

		sleep 5
		REBOOT=true
		reboot_system

	fi

	echo
    echo -e "\textensions download successfully finished"

	line 

	echo -e "\textensions integrity check"
	echo

	if [[ "$(ls -1 "$DOWNLOAD_DIR"/*tcz 2>/dev/null | wc -l )" == "0" ]]; then
	
		out "tcz packages for integrity check missing"
	
	fi

	for j in "$DOWNLOAD_DIR"/*.tcz; do


		md5_act="$(md5sum $j | awk '{print $1}' )"
		md5_orig="$(cat ${j}.md5.txt | awk '{print $1}')"

		printf "\t%-18s%-38s" "integrity check:" "$(basename $j)" 

		if [[ "$md5_orig" == "$md5_act" ]]; then

			stat=PASSED

		else

			stat=FAILED
			FAILED=1

		fi

		if [[ "$stat" == "PASSED" ]]; then

			printf "${GREEN}%-15s${NC}\n" "$stat"

		else

			printf "${RED}%-15s${NC}\n" "$stat"

		fi

		echo "*** integrity check for: $j *** $stat *** $md5_orig * $md5_act" >>$LOG

	done

	if [[ "$FAILED" == "1" ]]; then

		echo
		echo -e "\t${RED}ERROR:   extension integrity issue detected${NC}"
		echo -e "\t${RED}         so far nothing has been changed${NC}"
		echo -e "\t${RED}         try later or choose different repo after reboot${NC}"
		sleep 5
		REBOOT=true
		reboot_system

	else

		echo
		echo -e "\tsaving extensions"
		mv -f $DOWNLOAD_DIR/* $TARGET_DIR

	fi
}


load_extensions() {

    echo -e "\tloading extensions"
    
    # Load critical dependencies first (needed for git clone)
    echo -e "\t  loading git dependencies..."
    for dep in expat2 curl; do
        pcp-load -s -l -i "$dep" >>$LOG 2>&1
    done
    
    # Load all other extensions
    echo "$EXTENSIONS_LOAD" | while IFS= read -r ext; do
        [ -n "$ext" ] && pcp-load -s -l -i "$ext" >>$LOG 2>&1
    done
    
    # Verify git works with HTTPS
    if ! git ls-remote https://github.com 2>&1 | grep -q "HEAD"; then
        echo -e "\t${RED}WARNING: git HTTPS may not work properly${NC}" | tee -a $LOG
    fi
}


download_squeezelite() {

    echo -e "\tdownloading squeezelite sources"
    if [[ -d "$BASE" ]]; then
        rm -rf $BASE
    fi
    
    echo -e "\t  (this may take several minutes...)"
    
    # Try primary repository first
    echo -e "\t  trying: $REPO_SL"
    timeout 600 git clone "$REPO_SL" $BASE >>$LOG 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "\t${YELLOW}Primary repo failed, trying fallback...${NC}"
        REPO_SL="$REPO_SL_FALLBACK"
        echo -e "\t  trying: $REPO_SL"
        timeout 600 git clone "$REPO_SL" $BASE >>$LOG 2>&1
        
        if [ $? -ne 0 ]; then
            echo -e "\t${RED}Git clone failed from both repositories${NC}"
            echo -e "\t${YELLOW}Tried:${NC}"
            echo -e "\t  - $REPO_SL_PRIMARY"
            echo -e "\t  - $REPO_SL_FALLBACK"
            echo -e "\t${YELLOW}Check log: $LOG${NC}"
            out "downloading squeezelite sources - check network/log"
        else
            echo -e "\t${GREEN}Using fallback repository${NC}"
        fi
    fi
}


install_squeezelite() {

    cd $BASE

    # Check if squeezelite-sc branch exists (soundcheck fork)
    if git branch -r | grep -q "origin/squeezelite-sc"; then
        echo -e "\t  using soundcheck branch"
        git checkout squeezelite-sc >>$LOG 2>&1 || out "git checkout sc branch"
        # we need to get the makefiles from the sc branch for master
        cp Makefile.sc* /tmp 2>/dev/null || echo "No Makefile.sc found, using default" >>$LOG
    else
        echo -e "\t  ${YELLOW}soundcheck branch not found, using master${NC}"
        echo -e "\t  ${YELLOW}Note: will use standard build process${NC}"
    fi

    if [[ "$1" == "master" ]] || [[ ! -f /tmp/Makefile.sc-rpi-ux-$variant ]]; then
        git checkout master >>$LOG 2>&1 || out "git checkout master branch"
    fi
    
    #get git commit id as attachment to version string
    GIT_COMMIT_ID=$(git -C $BASE rev-parse --short HEAD)
    
    #define CUSTOM_VERSION
    sed -i "/^#define CUSTOM_VERSION/d" $BASE/squeezelite.h
    sed -i "/#define MICRO_VERSION/a #define CUSTOM_VERSION -$VID-$GIT_COMMIT_ID" $BASE/squeezelite.h

    echo -e "\tbuilding"
    
    # Try soundcheck makefile first, fallback to standard build
    if [ -f /tmp/Makefile.sc-rpi-ux-$variant ]; then
        make -C $BASE -f /tmp/Makefile.sc-rpi-ux-$variant >>$LOG 2>&1
    else
        echo -e "\t  ${YELLOW}Using standard build (no soundcheck makefile)${NC}"
        # Standard squeezelite build for ARM
        OPTS="-DLINKALL -DFFMPEG -DRESAMPLE -DDSD -DIR"
        export CFLAGS="-O3 -march=armv8-a -mcpu=cortex-a76 -mtune=cortex-a76"
        make -C $BASE OPTS="$OPTS" >>$LOG 2>&1
    fi
    
    if [ $? -ne 0 ]; then
        out "compiling binary - check log: $LOG"
    fi
    
    strip -x $BASE/squeezelite
    echo -e "\tinstalling"
    sudo install --mode=755 -o root -g root $BASE/squeezelite $TCE/squeezelite-custom || out "installing binary"
}


verify_squeezelite() {

    echo -e "\tverifying binary"

    if $TCE/squeezelite-custom -? >/dev/null 2>&1; then

        VERSION=$($TCE/squeezelite-custom -? | grep "^Squeezelite" |\
                    awk '{print $2}' | sed -e 's/v//' -e 's/,//')
        echo
        echo -e "\t   ${GREEN}squeezelite $VERSION${NC}"
        echo

    else

        out "new binary not working"

    fi
}


activate_squeezelite() {

    echo -e "\tactivating binary"
    if [[ ! -f $TCE/squeezelite ]]; then

        ln -s $TCE/squeezelite-custom $TCE/squeezelite

    fi
    sed -i 's/SQBINARY="default"/SQBINARY="custom"/' $pcpcfg
}


mount_boot() {

    echo -e "\tmounting boot partition"
    
    # Check for RPi5 boot layout first
    if [ -f /boot/firmware/config.txt ]; then
        BOOT_MNT=/boot/firmware
        echo -e "\t  detected RPi5 boot layout (/boot/firmware)"
    else
        # Traditional mount
        if [[ ! -d $BOOT_MNT ]]; then 
           sudo mkdir -p $BOOT_MNT
        fi
        if grep -q "$BOOT_DEV" /proc/mounts; then
           sudo umount "$BOOT_DEV" 2>>$LOG || out "umounting boot"
        fi
        sudo mount $BOOT_DEV $BOOT_MNT 2>>$LOG || out "mounting boot"
    fi
    
    sleep 1
}


set_isolcpus() {

    echo -e "\tconfiguring CPU isolation"
    
    # Kernel 6.x requires domain,managed syntax
    KERN_MAJ=$(uname -r | cut -d'.' -f1)
    if [ "$KERN_MAJ" -ge "6" ]; then
        ISOL_PARAM="isolcpus=${ISOLCPUS},domain,managed"
        echo -e "\t  kernel 6.x detected, using: $ISOL_PARAM"
    else
        ISOL_PARAM="isolcpus=${ISOLCPUS}"
    fi
    
    sed -i "s/^CPUISOL=.*/CPUISOL=\"$ISOLCPUS\"/g" $pcpcfg
    
    if grep -q "isolcpus" $BOOT_MNT/cmdline.txt; then
        sudo sed -i "s/isolcpus[=][^ ]* /${ISOL_PARAM} /g" $BOOT_MNT/cmdline.txt
    else
        sudo sed -i "s/$/ ${ISOL_PARAM} /g" $BOOT_MNT/cmdline.txt
    fi
    
    sudo sed -i 's/  */ /g' $BOOT_MNT/cmdline.txt
}


set_affinity() {

    echo -e "\tconfiguring CPU affinities"
    sed -i -e 's/^SQLAFFINITY=.*/SQLAFFINITY="1,2"/g' \
           -e 's/^SQLOUTAFFINITY=.*/SQLOUTAFFINITY=""/g' $pcpcfg

    if ! cat $pcpcfg | grep "OTHER" | grep -q "\-A"; then 

        sed -i 's/^OTHER="/OTHER="-A /g' $pcpcfg

    fi
}


INSTALL() {

    echo -e "\tbuilding variant"
    echo
    echo -e "\t  ${YELLOW} $VARIANT${NC}"
    echo
    branch=$1
    variant=$2
    set_log
    check_space
    backup_extensions
    select_ext_repo
    line
    download_extensions
    line
    if [[ "$DOWNLOAD_SUCCESS" == "true" ]]; then
		verify_extensions
	fi
	line
	echo -e "\tloading extensions (this may take a few minutes...)"
	load_extensions
	echo -e "\t${GREEN}extensions loaded${NC}"
    line
    download_squeezelite
    install_squeezelite $branch
    verify_squeezelite
    activate_squeezelite
    if echo "$VARIANT" | grep -q "soundcheck"; then
        mount_boot
        set_isolcpus
        set_affinity
    fi
    save_config
    REBOOT=true
}

##########################################################
###removal

remove_squeezelite() {

    echo -e "\tremoving custom squeezelite binary"
    if [[ -f "$TCE/squeezelite-custom" ]]; then
   
        sudo rm $TCE/squeezelite*
        sed -i 's/SQBINARY="custom"/SQBINARY="default"/' $pcpcfg

    else

        echo -e "\t  >> no custom binary on system"

    fi
}


remove_squeezelite_custom_settings() {

    echo -e "\tremoving squeezelite custom settings"
    sed -i 's/^OTHER=.*/OTHER=""/g' $pcpcfg
}


restore_extensions() {

    if [[ -f "$sKitbase/$EXT_BA" ]]; then

        echo -e "\trestoring pre-installation extensions"
        cd $TCE
        rm -rf onboot.lst ./optional
        mv $sKitbase/$EXT_BA .
        tar xzf $EXT_BA
        chmod 775 ./optional
        chmod 664 onboot.lst ./optional/*
        rm $TCE/$EXT_BA

    fi
}


disable_isolcpus() {

    echo -e "\tdisabling cpu isolation"
    sudo sed  -i 's/isolcpus[=][^ ]*//g' $BOOT_MNT/cmdline.txt
    sed -i "s/^CPUISOL=.*/CPUISOL=\"\"/g" $pcpcfg
}


disable_affinity() {

    echo -e "\tdisabling affinity settings"
    sed -i -e 's/^SQLAFFINITY=.*/SQLAFFINITY=""/g' \
           -e 's/^SQLOUTAFFINITY=.*/SQLOUTAFFINITY=""/g' $pcpcfg
}


REMOVE() {

    remove_squeezelite
    remove_squeezelite_custom_settings
    restore_extensions
    mount_boot
    disable_isolcpus
    disable_affinity
    save_config
    REBOOT=true
}


###main#######################################
colors
license

header

check_pcp
env_set
menu

DONE
reboot_system
exit 0
##############################################
