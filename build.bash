#!/usr/bin/env bash

IMAGE_SET="no"
IMAGE_REQUIRED_COMPLETED="no"
IMAGE_NAME=""
IMAGE_LOOP_DEVICE=""
export IMAGE_ROOTFS_MOUNT="/tmp/rootfs"
export ARCH=""

export REQ_BUILDDIR="./.req_builddir"
export REQ_INSTALLDIR="./.req_installdir"
export OPT_BUILDDIR="./.opt_builddir"

export CC="$(realpath ${REQ_INSTALLDIR}/usr/bin/gcc)"
export CXX="$(realpath ${REQ_INSTALLDIR}/usr/bin/g++)"

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
    echo "q. Quit"
}

print_arch_menu() {
    echo "-- SELECT ARCH --"
    echo
    echo "1. x86_64"
    echo "2. aarch64"
}

print_install_menu() {
    echo "-- INSTALL SOFTWARE --"
    echo
    echo "1. Setup Compiler"
    echo "2. Build/Install Software"
}

select_option() {
    read -p "--> " choice
    echo ${choice}
}

cleanup() {
    echo "Cleaning up..."
    deselect_image
}

mount_partitions() {
    mkdir -p ${IMAGE_ROOTFS_MOUNT}

    sudo mount "${IMAGE_LOOP_DEVICE}p2" ${IMAGE_ROOTFS_MOUNT}
    sudo mkdir -p ${IMAGE_ROOTFS_MOUNT}/{bin,boot,dev,etc,home,lib,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
    sudo chmod 755 ${IMAGE_ROOTFS_MOUNT}/{bin,boot,etc,lib,mnt,root,run,sbin,srv,usr,var}
    sudo mount "${IMAGE_LOOP_DEVICE}p1" ${IMAGE_ROOTFS_MOUNT}/boot

    sudo mount --bind /dev ${IMAGE_ROOTFS_MOUNT}/dev
    sudo mount -t proc /proc ${IMAGE_ROOTFS_MOUNT}/proc
    sudo mount -t sysfs /sys ${IMAGE_ROOTFS_MOUNT}/sys
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
        
        mount_partitions
        ARCH="$(cat ${IMAGE_ROOTFS_MOUNT}/.arch)"
    fi

    IMAGE_SET="yes"

    return 0
}

deselect_image() {
    if [[ ${IMAGE_SET} == "no" ]]; then
        echo "No image selected"
        return 0
    fi

    sudo umount ${IMAGE_ROOTFS_MOUNT}/sys
    sudo umount ${IMAGE_ROOTFS_MOUNT}/proc
    sudo umount ${IMAGE_ROOTFS_MOUNT}/dev
    sudo umount ${IMAGE_ROOTFS_MOUNT}/boot
    sudo umount ${IMAGE_ROOTFS_MOUNT}

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

    print_arch_menu
    opt="$(select_option)"

    case "${opt}" in
        1)
            arch="x86_64"
            ;;
        2)
            arch="aarch64"
            ;;
        *)
            echo "Invalid option"
            return 0
            ;;
    esac

    if [[ -z "${name}" || -z "${size}" || -z "${bsize}" || -z "${rsize}" || -z "${arch}" ]]; then
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
    mount_partitions

    sudo sh -c "echo "${arch}" > ${IMAGE_ROOTFS_MOUNT}/.arch"

    export IMAGE_NAME="${name}"
    export ARCH="${arch}"

    return 0
}

install_required_software() {
    mkdir -p ${REQ_BUILDDIR} ${REQ_INSTALLDIR}

    # Loop through each file in the directory
    for file in required/*; do
        # Check if the file exists and is a regular file
        if [ -f "$file" ]; then
            # Append the absolute path of the file to the array
            file_path=("$(realpath "$file")")

            FOUND="$( ${file_path} test_installed ${ARCH} )"
            if [[ "${FOUND}" == "yes" ]]; then
                echo "${file_path} is already installed"
                read -p "Do you want to update ${file_path} (y/n) " cont
                if [[ "${cont}" != "y" ]]; then
                    continue
                fi
            fi

            if [[ "${FOUND}" != "no" && "${FOUND}" != "yes" ]]; then
                echo "${file_path}: ${FOUND}"
                return 0
            fi

            CXX=g++ CC=gcc ${file_path} build ${ARCH}
            CXX=g++ CC=gcc ${file_path} install ${ARCH}
        fi
    done

    IMAGE_REQUIRED_COMPLETED="yes"   
}

install_optional_software() {
    mkdir -p ${OPT_BUILDDIR}

    for file in build-scripts/*; do

        if [[ -f "$file" ]]; then
            file_path=("$(realpath "$file")")

            FOUND="$( ${file_path} test_installed ${ARCH} )"
            if [[ "${FOUND}" == "yes" ]]; then
                echo "${file_path} is already installed"
                read -p "Do you want to update ${file_path} (y/n) " cont
                if [[ "${cont}" != "y" ]]; then
                    continue
                fi
            fi

            if [[ "${FOUND}" != "no" && "${FOUND}" != "yes" ]]; then
                echo "${file_path}: ${FOUND}"
                continue
            fi

            read -p "Do you want to build/install ${file} (y/n)" cont
            if [[ "${cont}" != "y" ]]; then
                echo "Skipping..."
                continue
            fi

            ${file_path} build ${ARCH}
            ${file_path} install ${ARCH} 
        fi

    done
}

install_software() {
    if [[ "${IMAGE_SET}" == "no" ]]; then
        echo "Please select an image"
        return 0
    fi

    print_install_menu
    opt="$(select_option)"
    
    case "${opt}" in 
        1)
            install_required_software
            ;;
        2)
            install_optional_software
            ;;
        *)
            echo "Invalid option"
            return 0
            ;;
    esac
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
            install_software
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
