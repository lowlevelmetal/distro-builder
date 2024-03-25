#!/usr/bin/env bash

on_error() {
    echo "Build script failure"
    echo "Exiting..."

    exit 1
}

trap 'on_error $LINENO' ERR
PREFIX=""

_build() {
    arch="$1"
    threads="$(( $(nproc) - 2 ))"

    git clone git://gcc.gnu.org/git/gcc.git
    cd gcc

    mkdir -p ${REQ_INSTALLDIR}/usr

    ./configure --prefix="${PREFIX}" --disable-bootstrap --disable-multilib --enable-languages=c,c++
    make -j${threads}
}

_install() {
    cd gcc
    make install
}

if [[ -z "${REQ_BUILDDIR}" || -z "${REQ_INSTALLDIR}" ]]; then
    echo "Requirement directories not set"
    exit 1
fi

PREFIX="$(realpath "${REQ_INSTALLDIR}/usr")"

if [[ -z "$1" || -z "$2" ]]; then
    echo "Script option missing"
    exit 1
fi

cd ${REQ_BUILDDIR}

case "$1" in
    build)
        _build
        ;;
    install)
        _install
        ;;
    *)
        exit 1
esac

exit 0
