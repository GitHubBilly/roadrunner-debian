#!/usr/bin/env node
//
// @(#) clnt-nc-srvr-ss.js
//
const WebSocket = require('ws');

const hostname = 'revotics.slewsys.org'
const port = 30046;

//
// For some server self-signed certificates, disable certificate validation.
//
// process.env.NODE_TLS_REJECT_UNAUTHORIZED = 0;

// Add smallstep CA root certificate to certificate bundle.
process.env.NODE_EXTRA_CA_CERTS = '/usr/share/certs/root_ca.crt';

const ws = new WebSocket('wss://' + hostname + ':' + port);

ws.on('open', () => {
  ws.send('something');
});

ws.on('message', (data) => {
  console.log(data);
});
