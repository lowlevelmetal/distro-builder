#!/usr/bin/env bash

on_error() {
    echo "Build script failure"

    exit 1
}

trap 'on_error $LINENO' ERR
PREFIX="${IMAGE_ROOTFS_MOUNT}/usr"
RET="yes"

_test() {
    if [[ -e "${PREFIX}/lib/libc.so" ]]; then
        return 0
    fi
    
    RET="no"
}

_build() {
    arch="$1"
    threads="$(( $(nproc) - 2 ))"

    git clone https://sourceware.org/git/glibc.git
    cd glibc
    git checkout master
    git pull origin master

    rm -rf build
    mkdir -p build
    cd build

    ../configure CC="${CC}" --prefix="${PREFIX}"

    make -j${threads}
    cd ../../
}

_install() {
    cd glibc/build
    sudo make install
    cd ../../
}

cd ${OPT_BUILDDIR}

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

echo "${RET}"
