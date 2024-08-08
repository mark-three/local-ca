# local-ca

Set of scripts built from following Jamie Nguyen's great guide on building a local [OpenSSL Certificate Authority](https://jamielinux.com/docs/openssl-certificate-authority/). I highly recommend giving this a read and learning more about how certificate authorities work.

These scripts are not intended to be production ready or used for anything other than removing the annoying "Connection is not secure" messages when accessing internal, self hosted services. Using the certs that these scripts generate does weaken your security posture and all users are to do their own verification and due diligence and the software comes as-is with no warranty. 

## Usage
- Clone the repo
- Copy .env.example -> .env
- Update .env values at top of file (private key values and OpenSSL Cert subject values)
- Run create_root_intermediate_ca.sh to generate the Root CA, the Intermediate CA and the Root-Intermediate Chain CA
    - The Root-Intermediate Chain CA file (ca-chain.cert.pem) will need to be added as a Certificate Authority in Chrome, Firefox, etc
- Copy ./configs/systems/example.ext and update DNS / IP values at the bottom of the file, for example
    - [alt_names]
      DNS.1 = localhost
      DNS.2 = server01
      DNS.3 = server01.local
      DNS.4 = server01.internal
      IP.1 = 127.0.0.1
      IP.2 = 10.10.10.50
- Update create_system_cert.sh to use the system name
    - TODO: Update this script to accept system name as parameter to prevent this update
- Run create_system_cert.sh and copy the following files to add to desired services
    - ./output/systems/example/example-no-pass.key.pem
        - NOTE: The pass key requires as password to be used and is not suitable for most services.
        - TODO: Update/simplify this output to be less confusing
    - ./output/systems/example/example.cert.pem