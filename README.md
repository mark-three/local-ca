# local-ca

Set of scripts built from following Jamie Nguyen's great guide on building a local [OpenSSL Certificate Authority](https://jamielinux.com/docs/openssl-certificate-authority/). I highly recommend giving this a read and learning more about how certificate authorities work.

These scripts are not intended to be production ready or used for anything other than removing the annoying "Connection is not secure" messages when accessing internal, self hosted services. Using the certs that these scripts generate does weaken your security posture and all users are to do their own verification and due diligence and the software comes as-is with no warranty.

## Usage
- Clone the repo
- Copy .env.example -> .env
- Update .env values at top of file (private key values and OpenSSL Cert subject values)
- Run create_root_intermediate_ca.sh to generate the Root CA, the Intermediate CA and the Root-Intermediate Chain CA
    - The Root CA cert (./output/root/certs/ca.cert.pem) will need to be added as a Certificate Authority in Chrome, Firefox, etc - see "Trusting the CA" below
- Copy ./configs/systems/example.ext and update DNS / IP values at the bottom of the file, for example
    - [alt_names]
      DNS.1 = localhost
      DNS.2 = server01
      DNS.3 = server01.local
      DNS.4 = server01.internal
      IP.1 = 127.0.0.1
      IP.2 = 10.10.10.50
- Run create_system_cert.sh --system SYSTEM_NAME and copy the following files to add to desired services
    - ./output/systems/example/example-no-pass.key.pem
        - NOTE: The pass key requires as password to be used and is not suitable for most services.
        - TODO: Update/simplify this output to be less confusing
    - ./output/systems/example/example.fullchain.cert.pem
        - IMPORTANT: Point services at the fullchain file (leaf + intermediate), NOT the bare example.cert.pem. Clients only trust the Root/Intermediate CA, so the server must send the intermediate cert on the wire. Browsers hide a missing intermediate by fetching it themselves (AIA chasing), but curl, openssl, python requests, etc. deliberately do not and will fail with "unable to get local issuer certificate".
        - The bare example.cert.pem is still generated for the rare service that wants the leaf and chain as separate inputs.

- To replace a system cert
    - run revoke_system_cert.sh --system SYSTEM_NAME
    - run create_system_cert.sh --system SYSTEM_NAME

## Trusting the CA

Two separate trust stores need the CA installed:

- Browsers (Chrome, Firefox, etc.) use their own trust database (NSS, ~/.pki/nssdb), not the OS one. Import the ROOT CA cert (./output/root/certs/ca.cert.pem) as a Certificate Authority in the browser settings.
    - Do not import ca-chain.cert.pem for this: most browser import paths (Chrome's certificate manager, certutil) only read the FIRST cert in a multi-cert file, so you end up with only the intermediate installed and still have to import the root separately. The root is the trust anchor - with it installed (and services serving the fullchain file) nothing else is needed.
    - Chrome/Chromium on Linux can also be done from the CLI:
      certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n "Local Root CA" -i ./output/root/certs/ca.cert.pem
- CLI tools (curl, openssl, wget, python, etc.) use the system trust store. Run deploy_ca.sh to install the Root and Intermediate CA certs there. Do not copy the files by hand unless you follow these rules, which the script handles for you:
    - update-ca-certificates only ingests files under /usr/local/share/ca-certificates/ ending in .crt - a .pem file is silently ignored (no warning, it just never becomes trusted).
    - Each .crt file must contain exactly one certificate. The hashing step only reads the first cert in a multi-cert file, so installing ca-chain.cert.pem as one file silently drops the root. Install the root and intermediate as separate .crt files.
    - deploy_ca.sh verifies the install by checking both CA subjects appear in /etc/ssl/certs/ca-certificates.crt and reports "2 added" on first install.


## Other Resources
Tools and resources you should check before using the scripts in this repo.

- https://github.com/pasuder/simple-ca-manager
- https://arminreiter.com/2022/01/create-your-own-certificate-authority-ca-using-openssl/
- https://github.com/jtyers/openssl-util
- https://smallstep.com/certificates/
    - https://github.com/smallstep/certificates
- https://letsencrypt.org/docs/certificates-for-localhost/
