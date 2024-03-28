#!/usr/bin/env bash

on_error() {
    echo "Build script failure"

    exit 1
}

trap 'on_error $LINENO' ERR

PREFIX=""
