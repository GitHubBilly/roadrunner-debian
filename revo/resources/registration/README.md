# REVO.IO REGISTRATION PROCESS
Revo.io API server authorizes remote management requests to
authenticated clients by means of registered client TLS certificates.
For each new board, the generation and submission to Revo.io of a
unique self-signed client TLS certificate is part of the registration
process. End-users with Revo.io accounts can revoke old certificates
and generate replacement certificates in the event of a system
compromise.

The registration process includes:
* Generating a unique X-509 certificate for each board to securely
  access Revo.io,
* Installing a Revo.io public certificate for accessing
  each board from Revo.io,
* Publishing board info, including:
  - Hostname,
  - Machine ID
  - For each interface, it's name and  MAC,
  - Output of /proc/cmdline to identify board type

Later, when a remote management request is issued from a board for
Revo.io, the remote IP address will also be registered for
identification, e.g., by means of geolocation¹ ².

All certificates remain encrypted³ until Revo.io is contacted, e.g.,
to enable remote assistance. This reduces exposure to external attack
for both edge devices and Revo.io.

The root account should be locked by default and any ssh access should
be enabled only upon demand by the user.

¹ Python geolocation libraries include:
* [ip2geotools](https://github.com/tomas-net/ip2geotools)
* [ipinfo](https://github.com/ipinfo/python)
* [geopy](https://github.com/geopy/geopy)
* [geoip2](https://github.com/maxmind/GeoIP2-python)

² Example using Google Maps API (not working?):
```shell
 curl -H "Content-Type: application/json" -X POST -d '{"considerIp": true}' https://www.googleapis.com/geolocation/v1/geolocate?key=YOUR-API-KEY
```

³ See [Encrypt and decrypt files to public keys via OpenSSL](https://raymii.org/s/tutorials/Encrypt_and_decrypt_files_to_public_keys_via_the_OpenSSL_Command_Line.html)

# TRANSPORT LAYER SECURITY
The Transport Layer Security (TLS) protocol requires only the
server side of a connection to have a TLS certificate, which
may be either signed by a certificate authority (CA) (e.g., [Let's
Encrypt](https://letsencrypt.org)) or "self-signed".

A CA-signed certificate can be validated by a client using the
trusted CA's public key. The domain name bound to the TLS
certificate must also match that used by the client to access the
server.

In the case of a server with a self-signed certificate, a client must
have a copy of (the public portion of) that certificate prior to
initiating a TLS connection. Validation is implicit, so the means by
which a self-signed certificate is distributed (and protected) must be
trusted. As with a CA-signed certificate, the domain name bound to
self-signed server certificate must match that used by the client to
access the server.

Servers may choose to restrict access to clients that can be
authenticated with TLS certificates. Client certificates are generally
self-signed, so the server must have a copy prior to accepting a
connection. Since clients generally don't have an IP addresses that a
server can verify through name resolution (DNS), the domain name bound
to a self-signed client certificate need not match the IP address from
which a client accesses the server. Consequently, client authenti-
cation is intrinsically less secure than server authentication.

# TLS CERTIFICATES
Self-signed, unencrypted, client/server RSA certificates with 10-year
expiration can be created with:

```
for role in client server; do
    openssl req -x509 -newkey rsa:4096 -nodes -days 3650 -sha256 \
            -keyout "${role}.key" -out "${role}.pem" -subj "/CN=$(hostname -f)"
done
```

Each certificate is split into two files: a private key with _.key_
extension and public certificate with _.pem_ extension. The contents
of the client certificate can be displayed in human-readable form
with:

```
openssl x509 -text -noout -in client.pem
```

A match between a private key and public certificate can be verified with:

```
if test "$(openssl x509 -noout -modulus -in client.pem)" = \
        "$(openssl rsa -noout -modulus -in client.key)"; then
    echo "key and certificate match"
else
    echo "key and certificate mismatch"
fi
```


# TLS PROGRAMMING
The following table provides examples of the TLS authenticated clients
and servers in Python as outlined above. Certificate revocation
([OCSP](https://en.wikipedia.org/wiki/Online_Certificate_Status_Protocol))
is not handled in the current implementation of these scripts.

When a web app is served by a web server, the web server is
responsible for the initial TLS handshake. In this case, client TLS
authentication requires a different strategy - a reverse
HTTP proxy seems to be a common strategy. For OCSP stapling, see,
e.g., [stapled](https://github.com/greenhost/stapled).

| Protocol  | Server Certificate                       | Client Certificate | Client | Server |
|-----------|------------------------------------------|--------------------|--------|--------|
| Socket    | [Let's Encrypt](https://letsencrypt.org) | Self-signed | [clnt-ss-srvr-cs.py](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/python/clnt-ss-srvr-cs.py)        | [srvr-cs-clnt-ss.py](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/python/srvr-cs-clnt-ss.py)
| Socket    | [Let's Encrypt](https://letsencrypt.org) | None               | [clnt-nc-srvr-cs.py](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/python/clnt-nc-srvr-cs.py)       | [srvr-cs-clnt-nc.py](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/python/srvr-cs-clnt-nc.py)
| Socket    | Self-signed                              | Self-signed        | [clnt-ss-srvr-ss.py](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/python/clnt-ss-srvr-ss.py)       | [srvr-ss-clnt-ss.py](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/python/srvr-ss-clnt-ss.py)
| Socket    | Self-signed                              | None               | [clnt-nc-srvr-ss.py](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/python/clnt-nc-srvr-ss.py)       | [srvr-ss-clnt-nc.py](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/python/srvr-ss-clnt-nc.py)
| WebSocket    | [Let's Encrypt](https://letsencrypt.org) | Self-signed | [clnt-ss-srvr-cs.js](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/javascript/ws/clnt-ss-srvr-cs.js)        | [srvr-cs-clnt-ss.js](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/javascript/ws/srvr-cs-clnt-ss.js)
| WebSocket    | [Let's Encrypt](https://letsencrypt.org) | None               | [clnt-nc-srvr-cs.js](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/javascript/ws/clnt-nc-srvr-cs.js)       | [srvr-cs-clnt-nc.js](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/javascript/ws/srvr-cs-clnt-nc.js)
| WebSocket    | Self-signed                              | Self-signed        | [clnt-ss-srvr-ss.js](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/javascript/ws/clnt-ss-srvr-ss.js)       | [srvr-ss-clnt-ss.js](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/javascript/ws/srvr-ss-clnt-ss.js)
| WebSocket    | Self-signed                              | None               | [clnt-nc-srvr-ss.js](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/javascript/ws/clnt-nc-srvr-ss.js)       | [srvr-ss-clnt-nc.js](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/javascript/ws/srvr-ss-clnt-nc.js)
