#!/usr/bin/env bash

IMAGE_SET="no"
IMAGE_NAME=""
IMAGE_LOOP_DEVICE=""
IMAGE_ROOTFS_MOUNT="/tmp/rootfs"

on_error() {
    echo "Fatal error occured. Exiting for safety"
    echo "Handles and mounts may still be open on your machine"
    echo "Tread carefully"

    cleanup

    exit 1
}

trap 'on_error $LINENO' ERR

print_main_menu() {
    echo "-- MAIN MENU --"
    echo
    echo "1. Create Base Image"
    echo "2. Build Software"
    echo "3. Select Image"
    echo "4. Deselect Image"
    echo "5. Help"
}

select_option() {
    read -p "--> " choice
    echo ${choice}
}

cleanup() {
    echo "Cleaning up..."
    deselect_image
}

select_image() {
    if [[ ${IMAGE_SET} == "yes" ]]; then
        echo "Please deselect current image first"
        return 1
    fi

    name="$1"
    if [[ -z "${name}" ]]; then
        echo "Please specify an image name"
        return 1
    fi

    export IMAGE_LOOP_DEVICE=$(sudo losetup --partscan --find --show ${name})
    if [[ $? != 0 ]]; then
        return 1
    fi

    if [[ "$2" == "yes" ]]; then
        echo "Mounting partitions"
        
        sudo mount "${IMAGE_LOOP_DEVICE}p2" ${IMAGE_ROOTFS_MOUNT}
        sudo mount "${IMAGE_LOOP_DEVICE}p1" ${IMAGE_ROOTFS_MOUNT}/boot 
    fi

    IMAGE_SET="yes"

    return 0
}

deselect_image() {
    if [[ ${IMAGE_SET} == "no" ]]; then
        echo "No image selected"
        return 1
    fi

    sudo umount ${IMAGE_LOOP_DEVICE}p1
    sudo umount ${IMAGE_LOOP_DEVICE}p2

    sudo losetup -d ${IMAGE_LOOP_DEVICE}

    export IMAGE_SET="no"

    echo "Image deselected"
    return 0
}

create_base_image() {
    if [[ ${IMAGE_SET} == "yes" ]]; then
        echo "Please deselect current image first"
        return 1
    fi

    read -p "Enter name of image file: " name
    read -p "Enter size of image file: " size
    read -p "Boot partition size in MiB: " bsize
    read -p "Root partition size in % of remaining space: " rsize

    if [[ -z "${name}" || -z "${size}" || -z "${bsize}" || -z "${rsize}" ]]; then
        echo "Invalid build option detected"
    fi

    echo "You will be writing over ${name}"
    read -p "Do you want to continue? (y/n): " c
    if [[ "$c" != "y" ]]; then
        echo "Not continuing"
        return 0
    fi    

    # DD image
    sudo dd if=/dev/zero of="${name}" bs=1M count="${size}"

    # Select image
    select_image "${name}"
    echo "Image loop device ${IMAGE_LOOP_DEVICE}"

    # Create partitions
    sudo parted -s "${IMAGE_LOOP_DEVICE}" mklabel gpt
    sudo parted -s "${IMAGE_LOOP_DEVICE}" mkpart boot 1MiB $(( ${bsize} + 1 ))MiB
    sudo parted -s "${IMAGE_LOOP_DEVICE}" mkpart root $(( 2 + ${bsize} ))MiB ${rsize}%
    sudo parted -s "${IMAGE_LOOP_DEVICE}" set 1 boot on

    # Format partitions
    sudo mkfs.vfat "${IMAGE_LOOP_DEVICE}"p1
    sudo mkfs.ext4 "${IMAGE_LOOP_DEVICE}"p2

    # Mount partitions and create initial directory structure
    sudo mount "${IMAGE_LOOP_DEVICE}p2" ${IMAGE_ROOTFS_MOUNT}
    sudo mkdir -p ${IMAGE_ROOTFS_MOUNT}/{bin,boot,dev,etc,home,lib,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
    sudo chmod 755 ${IMAGE_ROOTFS_MOUNT}/{bin,boot,etc,lib,mnt,root,run,sbin,srv,usr,var}
    sudo mount "${IMAGE_LOOP_DEVICE}p1" ${IMAGE_ROOTFS_MOUNT}/boot

    export IMAGE_NAME="${name}"

    return 0
}

echo "Linux Distrobution Builder"

while true; do

    print_main_menu
    choice=$(select_option)

    case "${choice}" in
        1)
            create_base_image           
            ;;
        2)
            ;;
        3)
            read -p "Image: " img
            select_image ${img} yes
            ;;
        4)
            deselect_image
            ;;
        5)
            ;;
        q)
            cleanup
            exit 0
            ;;
        *)
            echo "Invalid choice."
            continue
            ;;
    esac

done
