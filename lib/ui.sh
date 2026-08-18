#!/usr/bin/env bash
# Shared output helpers. dev-env, dev-vm and dev-secrets each had their own
# copy of these three functions.

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
}
