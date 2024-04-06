#!/usr/bin/env bash

on_error() {
    echo "Build script failure"
    echo "Exiting..."

    exit 1
}

trap 'on_error $LINENO' ERR
PREFIX=""
RET="yes"

# Build routine
_build() {
    arch="$1"
    threads="-j$(( $(nproc) - 2 ))"

    git clone git://gcc.gnu.org/git/gcc.git
    cd gcc
    git pull origin master

    mkdir -p ${REQ_INSTALLDIR}/usr

    make distclean
    ./configure --prefix="${PREFIX}" --disable-bootstrap --disable-multilib --enable-languages=c,c++
    make ${threads}
}

# Install routine
_install() {
    cd gcc
    make install
}

# Check for valid install routine
_test() {
    if [[ -e "${REQ_INSTALLDIR}/usr/bin/gcc" ]]; then
        return 0
    fi

    if [[ -e "${REQ_INSTALLDIR}/usr/bin/g++" ]]; then
        return 0
    fi

    RET="no"
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
    test_installed)
        _test
        ;;
    *)
        exit 1
esac

echo "${RET}"

exit 0
