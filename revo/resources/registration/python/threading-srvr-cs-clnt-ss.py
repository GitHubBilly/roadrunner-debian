#!/usr/bin/env python3
#
# This script demonstrates a secure threading TCP/IP server. It
# requires that its clients authenticate with a self-signed
# certificate (the public part of which must be contained in
# ./clients.pem before the server starts). The server itself uses a
# TLS certificate signed by LetsEncrypt.org, which the client
# validates with LetsEncrypt's public key.
#
# Upon accepting a client connection, the server receives from the client its
# hostname and sends to the client its external IP address.
#
import socket, socketserver, ssl, threading

class RequestHandler(socketserver.BaseRequestHandler):

    def handle(self):
        print(f'Connection from: {self.client_address[0]}:{self.client_address[1]}')
        try:
            cert = self.request.getpeercert()
            if cert:
                print(f'cert: {cert}')
            else:
                raise ValueError()

            data = self.request.recv(1024)
            if data:
                print(f'got: {data}')
            self.request.send(f'{self.client_address[0]}'.encode())
        except Exception as err:
            print(f'Exception: {err}: {self.client_address[0]}:{self.client_address[1]}')


class ThreadingServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    request_queue_size = 100

    def __init__(self, config, RequestHandlerClass, bind_and_activate=True):
        super().__init__((config['host'], config['port']),
                         RequestHandlerClass, False)

        context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        context.verify_mode = ssl.CERT_REQUIRED
        context.load_cert_chain(certfile=config['fullchain'],
                                keyfile=config['serverkey'])
        context.load_verify_locations(cafile=config['clientspem'])
        self.socket = context.wrap_socket(self.socket, server_side=True)
        if (bind_and_activate):
            self.server_bind()
            self.server_activate()
            print(f"Listening on: {config['host']}:{config['port']}")


if __name__ == '__main__':
    config = {
        'host' : 'revotics.slewsys.org',
        'port' : 30046,
        'fullchain' : '/etc/letsencrypt/live/revotics.slewsys.org/fullchain.pem',
        'serverkey' : '/etc/letsencrypt/live/revotics.slewsys.org/privkey.pem',
        'clientspem' : 'clients.pem'
    }

    with ThreadingServer(config, RequestHandler) as server:
        server.serve_forever()
        # server_thread = threading.Thread(target=server.serve_forever)
        # server_thread.daemon = True
        # server_thread.start()
