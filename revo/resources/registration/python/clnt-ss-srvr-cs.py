#!/usr/bin/env python3
#
# @(#) clnt-ss-srvr-cs.py
#
# This script implements a TLS client that authenticates itself to the
# server with a self-signed (ss) TLS certificate and authenticates the
# server with a TLS certficate signed (cs) by Let's Encrypt.
#
import socket, ssl

def ssl_client(config):
    DOTTED_QUAD_LEN_MAX = 15

    context = ssl.create_default_context()
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_cert_chain(certfile=config['clientpem'],
                            keyfile=config['clientkey'])

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
        'clientpem' : '../certs/client-1.pem',
        'clientkey' : '../certs/client-1.key',
        'serverpem' : '../certs/server.pem'
    }

    print(f"Requesting TLS connection to: {config['host']}:{config['port']}")
    ssl_client(config)
