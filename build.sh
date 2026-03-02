#!/bin/bash

# ===================================================================
# MikuXFrierenOS - Build Script
# Using Samsung AP Firmware 
# Device supported (and tested): SM-G996B/DS SM-G996B (S21+ | t2s)
# Author: Bibouwunet
# ==================================================================


set -e # stop if any error that would corrupt the file..


# =================================================================
# CONFIG

firmware_version="G996BXXSJHZA6"
super_size=11429478400
vendor_size=1587580928
product_size=1648750592
odm_size=4349952

stock_dir="./stock"
work_dir="./work"
output_dir="./output"

dependencies=("samloader3" "unlz4" "lz4" "simg2img" "img2simg" "lpunpack" "lpmake" "lpdump" "tar" "python3")

imei="355399273528593"

# =================================================================



# =================================================================
# COLORS

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()    { echo -e "${CYAN}[*] $1${NC}"; }
success(){ echo -e "${GREEN}[✓] $1${NC}"; }
warn()   { echo -e "${YELLOW}[!] $1${NC}"; }
error()  { echo -e "${RED}[✗] $1${NC}"; exit 1; }
# ================================================================



# ===============================================================
# SETUP

setup() {
	sudo -v
	while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
	
	# check if theres enough space
	free_space=$(df -BG . | awk 'NR==2 {gsub("G","",$4); print $4}')
	if [ "$free_space" -lt 60 ]; then
    		error "not enough free space! need atleast 60GB, got ${free_space}GB"
	fi
	log "free space: ${free_space}GB "

	log "creating directories p_p"
	mkdir -p "$work_dir/super_extracted"
	mkdir -p "$work_dir/system_mount"
	mkdir -p "$output_dir"
	mkdir -p "$stock_dir"
	success "directories created successfuly :3"
}
# ===============================================================



# ===============================================================
# DOWNLOAD official rom

download() {
    log "checking latest firmware version..."
    fw_ver=$(echo -e "setimei ${imei}\nlist\nexit" | samloader3 -M "SM-G996B" -R "BOG" | grep "True" | grep -oP 'G\w+/\w+/\w+/\w+')
    log "downloading firmware version $fw_ver..."
    echo -e "setimei ${imei}\ndownload $fw_ver --decrypt -o $stock_dir/firmware.zip.enc4\nexit" | samloader3 -M "SM-G996B" -R "BOG"
    mv "$stock_dir/firmware.zip." "$stock_dir/firmware.zip" 2>/dev/null || true
    success "firmware downloaded to $stock_dir/"
}
# ===============================================================



# ===============================================================
# CHECK DEPENDENCIES

check_dependencies() {
	log "checking if all the dependencies are installed"
	MISSING=()

	for dep in "${dependencies[@]}";do
		if ! command -v "$dep" &>/dev/null; then
			MISSING+=("$dep")
		fi
	done

	if [ ${#MISSING[@]} -ne 0 ]; then
		error "missing dependencies: ${MISSING[*]}\ninstall with sudo pacman -S android-tools"
	fi

	success "wooo all dependencies found"
}

# ===========================================================



# ===============================================================
# EXTRACT

extract() {
	log "Extracting AP firmware...."

	if [ -f "$stock_dir/firmware.zip" ]; then
		log "unziping"
		unzip -o "$stock_dir/firmware.zip" -d "$stock_dir/"
	fi

	ap_file=$(ls "$stock_dir"/AP_${firmware_version}_*.md5 2>/dev/null | head -1)
    	if [ -z "$ap_file" ]; then
        	error "AP firmware file not found in $stock_dir"
    	fi
    
    	tar -xf "$ap_file" -C "$work_dir"/

	log "Decompressing super.img.."
	unlz4 "$work_dir/super.img.lz4" "$work_dir/super.img"

	log "converting sparse to raw"
	simg2img "$work_dir/super.img" "$work_dir/super_raw.img"

	log "extracting super partition (fun part it might fail~)"
	lpunpack "$work_dir/super_raw.img" "$work_dir/super_extracted/"

	success "EXTRACTION COMPLETE!!"
}

# ===============================================================



# ===============================================================
# MOUNT

mount_system() {
	log "mounting system partition.."
	sudo mount -o rw,loop "$work_dir/super_extracted/system.img" "$work_dir/system_mount/"
	success "System partition was mounted at $work_dir/system_mount/"
}

# ===============================================================



# ===============================================================
# DEBLOAT 

debloat() {
	log "removing useless crap that samsung is paid for adding by default smh"
	system_app="$work_dir/system_mount/system/app"
	BLOAT=(
	       "BlockchainBasicKit"
        	"KidsHome_Installer"
        	"MinusOnePage"
        	"Netflix_activationCommon"
        	"Netflix_stub"
        	"FBAppManager_NS"
        	"Fast"
        	"MoccaMobile"
        	"MdecService"
        	"MDMApp"
        	"BasicDreams"
        	"GooglePrintRecommendationService"
        	"ParentalCare"
        	"P2pAwareOverlay"
        	"PacProcessor"
    	)

	for app in "${BLOAT[@]}"; do
		if [ -d "$system_app/$app" ]; then
			sudo rm -rf "$system_app/$app"
			success "yonked $app"
		else
			warn "$app 404, skipping"
		fi
	done

	success "Debloat complete"
}

# ===============================================================



# ===============================================================
# UNMOUNT

unmount_system() {
	log "unmounting system partition"
	sudo umount -l "$work_dir/system_mount/"
	success "unmounted successfuly"
}

# ===============================================================



# ===============================================================
# REPACK

repack() {
	log "checking and shrinking system.img.............."
	sudo e2fsck -f "$work_dir/super_extracted/system.img"
	sudo resize2fs -M "$work_dir/super_extracted/system.img"

	log "converting partitions to sparse"
	img2simg "$work_dir/super_extracted/system.img"  "$work_dir/super_extracted/system_sparse.img"
	img2simg "$work_dir/super_extracted/vendor.img"  "$work_dir/super_extracted/vendor_sparse.img"
    	img2simg "$work_dir/super_extracted/product.img" "$work_dir/super_extracted/product_sparse.img"
    	img2simg "$work_dir/super_extracted/odm.img"     "$work_dir/super_extracted/odm_sparse.img"

    	system_size=$(du -b "$work_dir/super_extracted/system.img" | cut -f1)
    	log "System size: $system_size bytes"

	log "Rebuilding super.img"
	lpmake \
		--metadata-size 65536 \
		--super-name super \
		--metadata-slots 2 \
		--device super:${super_size} \
		--partition system:readonly:${system_size}:default \
		--image system="$work_dir/super_extracted/system_sparse.img" \
        	--partition vendor:readonly:${vendor_size}:default \
        	--image vendor="$work_dir/super_extracted/vendor_sparse.img" \
        	--partition product:readonly:${product_size}:default \
        	--image product="$work_dir/super_extracted/product_sparse.img" \
        	--partition odm:readonly:${odm_size}:default \
        	--image odm="$work_dir/super_extracted/odm_sparse.img" \
       		--sparse \
       		--output "$work_dir/super_new.img"

	log "compressing super.img"
	lz4 -B6 --content-size "$work_dir/super_new.img" "$work_dir/super.img.lz4"
	
	log "packing into odin tar file format.."
	tar -H ustar -c -C "$work_dir" super.img.lz4 -f "$output_dir/APMikuXFrierenOS.tar"
    	md5sum -t "$output_dir/APMikuXFrierenOS.tar" >> "$output_dir/APMikuXFrierenOS.tar"
    	mv "$output_dir/APMikuXFrierenOS.tar" "$output_dir/APMikuXFrierenOS.tar.md5"
	
	success "repack complete!! -> $output_dir/APMikuXFrierenOS.tar.md5"
}


# ===========================================================
# CLEAN

clean() {
    warn "Cleaning work directory..."
    rm -rf "$work_dir"/*
    success "Work directory cleaned"
}

# ==========================================================



# =========================================================
# MAIN

case "$1" in
    setup)    setup && check_dependencies ;;
    download) setup && download ;;
    extract)  setup && extract ;;
    mount)    mount_system ;;
    debloat)  debloat ;;
    unmount)  unmount_system ;;
    repack)   repack ;;
    clean)    clean ;;
    all)      setup && download && extract && mount_system && debloat && unmount_system && repack ;;
    *)


        echo ""
        echo "  MikuXFrierenOS Build Script"
        echo "  Usage: ./build.sh [command]"
        echo ""
        echo "  Commands:"
	echo "    download  - Download stock firmware"
        echo "    extract   - Extract AP firmware"
        echo "    mount     - Mount system partition"
        echo "    debloat   - Remove bloat apps"
        echo "    unmount   - Unmount system partition"
        echo "    repack    - Repack into flashable tar"
        echo "    clean     - Clean work directory"
        echo "    all       - Run everything at once"
        echo ""
        ;;
esac

# =========================================================
