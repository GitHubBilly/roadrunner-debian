#!/usr/bin/env node
//
// @(#) clnt-ss-srvr-ss.js
//
var fs = require('fs');
const WebSocket = require('ws');

const hostname = 'revotics.slewsys.org'
const port = 30046;
const key = '/usr/share/certs/private/diva.key';
const cert = '/usr/share/certs/diva.crt';
const options = {
    key: fs.readFileSync(key),
    cert: fs.readFileSync(cert)
};

//
// For server private certificates, disable certificate validation.
//
process.env.NODE_TLS_REJECT_UNAUTHORIZED = 0;

const ws = new WebSocket('wss://' + hostname + ':' + port, options);

ws.on('open', () => {
  ws.send('something');
});

ws.on('message', (data) => {
  console.log(data);
});
