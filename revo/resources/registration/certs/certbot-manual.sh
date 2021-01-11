#!/usr/bin/env bash
#
# @(#) certbot-manual.sh
#
# This script issues a manual TLS certificate signing request to Let's
# Encrypt for a primary domain and, optionally, its wildcard
# subdomains. Upon successful completion, signed TLS certificates are
# placed under /etc/letsencrypt/live/${primary_domain}/. In
# particular, servers will typically use:
#
# /etc/letsencrypt/live/revotics.slewsys.org/fullchain.pem
#
#
# As part It solicits a DNS challenge to confirm domain ownership.  Let's Encrypt
# prompts for two DNS TXT records to be published under the primary domain.
#
# The result is TXT records in the BIND9 data base for the primary
# domain along the lines of:
#
#     _acme-challenge 300 IN TXT	QwV5kXFyC4NW2fS0PBYY5bX-GkQOkiwbJRziR7Mv828
#
# The DNS server must reload its data bases after each record is added:
#
#    $ sudo rndc reload
#
declare email=slewsys@icloud.com
declare primary_domain=revotics.slewsys.org
declare include_wildcard_subdomains=false
declare dry_run=false

declare -a certbot_args=(
    --manual
    --rsa-key-size 4096
    --preferred-challenges dns
    --agree-tos
    -m "$email"
    -d "$primary_domain"
)

if $dry_run; then
    certbot_args+=( --dry-run )
fi

if $include_wildcard_subdomains; then
    certbot_args+=( -d "*.${primary_domain}" )
fi

certbot certonly "${certbot_args[@]}"
