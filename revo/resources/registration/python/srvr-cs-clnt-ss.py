#!/usr/bin/env python3
#
# @(#) srvr-cs-clnt-ss.py
#
# This script implements a TLS server that uses certificates signed (cs)
# by Let's Encrypt and authenticates clients with self-signed (ss)
# TLS certificates.
#
import selectors, socket, ssl

sel = selectors.DefaultSelector()

def accept(ssock, mask):
    try:
        conn, addr = ssock.accept()
    except ssl.SSLError as err:
        print(f'SSLError: {err}')
        return

    cert = conn.getpeercert()
    print(f'Accepting TLS connection from: {addr[0]}:{addr[1]}')
    print(f'Cipher: {conn.cipher()}')
    print(f'Certificate: {cert}')

    # Disable I/O blocking after TLS handshake
    conn.setblocking(False)
    sel.register(conn, selectors.EVENT_READ, exchange)

def exchange(conn, mask):
    NAME_LEN_MAX = 253

    try:
        peeraddr, peerport = conn.getpeername()
        domain_name = conn.recv(NAME_LEN_MAX)
        if domain_name:
            print(f"Received: {domain_name.decode('utf-8')} from: {peeraddr}:{peerport}")
        conn.send(peeraddr.encode('utf-8'))
    finally:
        sel.unregister(conn)
        conn.close()

def ssl_event_loop(config):
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_cert_chain(certfile=config['fullchain'],
                            keyfile=config['serverkey'])
    context.load_verify_locations(cafile=config['clientspem'])

    # Python 3.8 provides convenience function:
    # with socket.create_server((config['host'], config['port']),
    #                           reuse_port=True, backlog=100) as sock:

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((config['host'], config['port']))
        sock.listen(100)
        print(f"Listening on: {config['host']}:{config['port']}")

        with context.wrap_socket(sock, server_side=True) as ssock:
            sel.register(ssock, selectors.EVENT_READ, accept)
            while True:
                try:
                    events = sel.select()
                    for key, mask in events:
                        callback = key.data
                        callback(key.fileobj, mask)
                except KeyboardInterrupt:
                    break

if __name__ == '__main__':
    config = {
        'host' : 'revotics.slewsys.org',
        'port' : 30046,
        'serverkey' : '/etc/letsencrypt/live/revotics.slewsys.org/privkey.pem',
        'fullchain' : '/etc/letsencrypt/live/revotics.slewsys.org/fullchain.pem',
        'clientspem' : '../certs/clients.pem'
    }

    ssl_event_loop(config)
