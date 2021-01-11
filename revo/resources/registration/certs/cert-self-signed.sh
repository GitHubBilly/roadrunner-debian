#!/usr/bin/env bash
#
# @(#) gen-self-signed-cert
#
declare role=${1:-'client'}
declare cn=${2:-"$(hostname -f)"}

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes  -keyout "${role}.key" -out "${role}.pem" -subj "/CN=${cn}"
