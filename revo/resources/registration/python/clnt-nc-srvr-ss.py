#!/usr/bin/env python3
#
# @(#) clnt-nc-srvr-ss.py
#
# This script implements a TLS client that does not use certificates (nc)
# and authenticates the server with a self-signed (ss) TLS certificate.
#
import socket, ssl

def ssl_client(config):
    DOTTED_QUAD_LEN_MAX = 15

    context = ssl.create_default_context(cafile=config['serverpem'])
    context.verify_mode = ssl.CERT_REQUIRED

    try:
        with socket.create_connection((config['host'], config['port'])) as sock:
            with context.wrap_socket(sock, server_hostname=config['host']) as ssock:
                cert = ssock.getpeercert()
                print(ssock.version())
                print(f'Certificate: {cert}')

                hostname = socket.getfqdn()
                ssock.send(hostname.encode('utf-8'))
                external_ip = ssock.recv(DOTTED_QUAD_LEN_MAX)
                print(f"External IP: {external_ip.decode('utf-8')}")
    except ssl.SSLError as err:
        print(f'SSLError: {err}')


if __name__ == '__main__':
    config = {
        'host' : 'revotics.slewsys.org',
        'port' : 30046,
        'serverpem' : '../certs/server.pem'
    }

    print(f"Requesting TLS connection to: {config['host']}:{config['port']}")
    ssl_client(config)
