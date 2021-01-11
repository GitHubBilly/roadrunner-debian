# REVO.io Certificate Authority
## Install Smallstep Certificate Authority
On Ubuntu x86\_64, run:

```
curl -L https://raw.githubusercontent.com/revolution-robotics/roadrunner-debian/debian_buster_rr01/revo/registration/certs/install-step-ca.sh | bash -s
```

[install-step-ca.sh](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/revo/registration/certs/install-step-ca.sh)

## Build `step` for ARM
To build `step-cli` for ARM,  create a Debian rootfs, e.g., see
 [Debian GNU/Linux build suite for REVO boards](https://github.com/revolution-robotics/roadrunner-debian))
with multipass VM manager, e.g., see
[mp-build-diskimage](https://github.com/revolution-robotics/roadrunner-debian/blob/debian_buster_rr01/contrib/mp-build-diskimage.sh),
and run:

```
cd roadrunner_debian
contrib/chrootfs.sh
```

From the QEMU virtual ARM rootfs, to build `step-cli` run:

```
sudo apt update
sudo apt install -y golang-go
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin v1.31.0
sudo install $(go env GOPATH)/bin/golangci-lint /usr/bin/
sudo apt install -y debhelper devscripts
mkdir $HOME/smallstep
cd $HOME/smallstep
git clone https://github.com/smallstep/cli.git
cd ./cli
make bootstrap
make changelog
make build
mv crypto/kdf/kdf_test.go{,~}
make debian
cd ..
```

TODO: Override dh_auto_test to speed up `make debian`.

## Build `step` for ARM

After building `step`, build `step-ca` with:

```
sudo apt install -y libpcsclite-dev
go get /root/go/pkg/mod/github.com/go-piv/piv-go@v1.6.0/piv/pcsc_linux.go
sed -i -e 's/8010002E/7FFFFFFF/'  /root/go/pkg/mod/github.com/go-piv/piv-go@v1.6.0/piv/pcsc_linux.go
go get /root/go/pkg/mod/github.com/go-piv/piv-go@v1.6.0/piv/pcsc_linux.go
git clone https://github.com/smallstep/certificates.git
cd ./certificates
cat >>debian/rules <EOF

override_dh_auto_clean:
	echo "dh_auto_clean: disabled"

override_dh_auto_test:
	echo "dh_auto_test: disabled"
EOF
make debian
cd ..
```


## Initialize Certificate Authority (EasyRSA)
Clone and deploy Certificate Authority utility, easyrsa, from GitHub:
```
git clone https://github.com/OpenVPN/easy-rsa.git
cd easy-rsa
revision=g$(git rev-parse HEAD | cut -c-7)
./build/build-dist.sh --version="$revision" --no-windows
ca_dist=EasyRSA-${revision}
sudo tar -C /etc -zxf dist-staging/${ca_dist}.tgz
cd /etc/${ca_dist}
sudo cp vars.example vars
diff_url=https://raw.githubusercontent.com/revolution-robotics/roadrunner-debian/debian_buster_rr01/revo/registration/certs/easyrsa-vars.diff
curl "$diff_url" | sudo patch
sudo ./easyrsa init-pki
sudo ./easyrsa build-ca nopass
sudo install -d -m 0755 /usr/share/certs
sudo install -m 0644 pki/ca.crt /usr/share/certs/
```
## Initialize Certificate Authority (CloudFlare)
Clone and deploy Certificate Authority utility, CFSSL, from GitHub:
```
snap install go --classic
git clone https://github.com/cloudflare/cfssl.git
cd cfssl
make
sudo install -d -m 755 /usr/local/bin
for cmd in bin/*; do sudo install -m 755 "$cmd" /usr/local/bin; done
```
