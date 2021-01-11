#!/usr/bin/env node
//
// @(#) srvr-cs-clnt-nc.js
//
const fs = require('fs');
const https = require('https');
const WebSocket = require('ws');
const url = require('url');

const port = 30046;
const cert = '/etc/letsencrypt/live/revotics.slewsys.org/fullchain.pem';
const key = '/etc/letsencrypt/live/revotics.slewsys.org/privkey.pem';
const options = {
    cert: fs.readFileSync(cert),
    key: fs.readFileSync(key)
};

//
// For server certificates signed by private CA, load private CA's
// certificate.
//
// process.env.NODE_EXTRA_CA_CERTS = '/usr/share/certs/ca.crt';

const server = https.createServer(options);
const wss = new WebSocket.Server({ noServer: true });


wss.on('connection', (ws) => {
  ws.on('message', (message) => {
    console.log('received: %s', message);
  });

  ws.send('something');
});

server.on('upgrade', (req, sock, head) => {
    const pathname = url.parse(req.url).pathname;

    console.log('pathname: ' + pathname);
    console.log(new Date() + ' ' +
                req.connection.remoteAddress + ' ' +
                req.method + ' ' + req.url);

    wss.handleUpgrade(req, sock, head, (ws) => {
        wss.emit('connection', ws, req);
    });
});

console.log('Listening on port: ' + port)
server.listen(port);
