#!/usr/bin/env node
var WebSocketServer = require('websocket').server;
var http = require('http');

var server = http.createServer(function(request, response) {
    console.log((new Date()) + ' Received request for ' + request.url);
    response.writeHead(404);
    response.end();
});

server.listen(8080, function() {
    console.log((new Date()) + ' Server is listening on port 8080');
});

wsServer = new WebSocketServer({
    httpServer: server,
    // You should not use autoAcceptConnections for production
    // applications, as it defeats all standard cross-origin protection
    // facilities built into the protocol and the browser.  You should
    // *always* verify the connection's origin and decide whether or not
    // to accept it.
    autoAcceptConnections: false
});

function refReplacer() {
  let m = new Map(), v= new Map(), init = null;

  return function(field, value) {
    let p= m.get(this) + (Array.isArray(this) ? `[${field}]` : '.' + field);
    let isComplex= value===Object(value)

    if (isComplex) m.set(value, p);

    let pp = v.get(value)||'';
    let path = p.replace(/undefined\.\.?/,'');
    let val = pp ? `#REF:${pp[0]=='[' ? '$':'$.'}${pp}` : value;

    !init ? (init=value) : (val===init ? val="#REF:$" : 0);
    if(!pp && isComplex) v.set(value, path);

    return val;
  }
}


function originIsAllowed(origin) {
  // put logic here to detect whether the specified origin is allowed.
  // console.log((new Date()) + ' Connection from origin ' + JSON.stringify(origin, refReplacer(), 4) + ' accepted.');
  console.log((new Date()) + ' Connection from origin ' + origin + ' accepted.');
  return true;
}

wsServer.on('request', function(request) {
    if (!originIsAllowed(request.remoteAddress)) {
      // Make sure we only accept requests from an allowed origin
      request.reject();
      console.log((new Date()) + ' Connection from origin ' + request.remoteAddress + ' rejected.');
      return;
    }

    var connection = request.accept('echo-protocol', request.remoteAddress);
    connection.on('message', function(message) {
        if (message.type === 'utf8') {
            console.log('Received Message: ' + message.utf8Data);
            connection.sendUTF(message.utf8Data);
        }
        else if (message.type === 'binary') {
            console.log('Received Binary Message of ' + message.binaryData.length + ' bytes');
            connection.sendBytes(message.binaryData);
        }
    });
    connection.on('close', function(reasonCode, description) {
        console.log((new Date()) + ' Peer ' + connection.remoteAddress + ' disconnected.');
    });
});
