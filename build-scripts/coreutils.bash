#!/usr/bin/env bash

# USED GLOBALS
# IMAGE_ROOTFS_MOUNT: The mount location of the selected image's root partition
# OPT_BUILDDIR: The directory to build optional software in. It is recommended to build
#   all optional software here

# This script is a great example of a distro-builder
# compatible build script

# This type of sanity check is not required but adds a level of safety

if [[ -z "${IMAGE_ROOTFS_MOUNT}" ]]; then
    echo "ERROR: IMAGE_ROOTFS_MOUNT is not set"
    exit 1
fi

if [[ -z "${OPT_BUILDDIR}" ]]; then
    echo "ERROR: OPT_BUILDDIR is not set"
    exit 1
fi

if [[ -z "${ARCH}" ]]; then
    echo "ERROR: ARCH is not set"
    exit 1
fi

on_error() {
    echo "Coreutils build script failure"

    exit 1
}

trap 'on_error $LINENO' ERR
PREFIX="${IMAGE_ROOTFS_MOUNT}" # IMAGE_ROOTFS_MOUNT is guaranteed to be set
BUILDDIR="${OPT_BUILDDIR}" # OPT_BUILDDIR is gauranteed to be set
THREADS="$(( $(nproc) - 2 ))"

# Make sure you have atleast one build thread
if [[ ${THREADS} < 1 ]]; then
    THREADS=1
fi

_build() {
    cd ${BUILDDIR}

    rm -rf coreutils
    
    git clone git://git.sv.gnu.org/coreutils
    cd coreutils
   
    ./bootstrap

    mkdir build
    cd build

    mkdir -p ${PREFIX}
    ../configure --without-selinux --without-included-regex --prefix=${PREFIX}

    make -j${THREADS}
}

_install() {
    cd ${BUILDDIR}/coreutils/build
    sudo make install
}

_test() {
    if [[ -e "${PREFIX}/bin/dd" ]]; then
        echo "yes"
        return 0
    fi

    echo "no"
}


case "${1}" in
    build)
        _build
        ;;
    install)
        _install
        ;;
    test_installed)
        _test
        ;;
    *)
        exit 1
        ;;
esac

