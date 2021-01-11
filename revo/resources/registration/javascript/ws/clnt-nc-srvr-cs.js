#!/usr/bin/env node
//
// @(#) clnt-nc-srvr-cs.js
//
const WebSocket = require('ws');

const hostname = 'revotics.slewsys.org'
const port = 30046;

//
// For server private certificates, disable certificate validation.
//
// process.env.NODE_TLS_REJECT_UNAUTHORIZED = 0;

const ws = new WebSocket('wss://' + hostname + ':' + port);

ws.on('open', () => {
  ws.send('something');
});

ws.on('message', (data) => {
  console.log(data);
});
