# local-ca

Set of scripts built from following Jamie Nguyen's great guide on building a local [OpenSSL Certificate Authority](https://jamielinux.com/docs/openssl-certificate-authority/). I highly recommend giving this a read and learning more about how certificate authorities work.

These scripts are not intended to be production ready or used for anything other than removing the annoying "Connection is not secure" messages when accessing internal, self hosted services. Using the certs that these scripts generate does weaken your security posture and all users are to do their own verification and due diligence and the software comes as-is with no warranty.

## Requirements

- `openssl`, `bash`, `getopt`
- [`just`](https://github.com/casey/just) for the task runner (optional - every recipe is a thin wrapper around a script you can run directly)
- `certutil` for browser trust: `sudo apt install libnss3-tools` (Debian/Ubuntu), `sudo dnf install nss-tools` (Fedora/RHEL), `sudo pacman -S nss` (Arch)

Run `just doctor` to check what is present and what is missing.

## Quick start

```sh
just init                    # create .env from .env.example, then edit it
just ca                      # create the Root CA, Intermediate CA and chain
just new-system server01     # scaffold configs/systems/server01.ext
$EDITOR configs/systems/server01.ext   # set the DNS / IP entries
just cert server01           # issue the certificate
just trust                   # trust the CA in the system and browser stores
```

Run `just` on its own to list every recipe.

## Recipes

| Recipe | What it does |
| --- | --- |
| `just init` | Create `.env` from `.env.example` |
| `just setup` | Install the git hooks (pre-commit, commit-msg, pre-push) |
| `just doctor` | Check the required tooling is installed |
| `just ca` | Create the Root CA, Intermediate CA and chain (prompts before overwriting) |
| `just new-system NAME` | Scaffold `configs/systems/NAME.ext` from the example |
| `just cert NAME` | Issue a certificate for a system |
| `just revoke NAME` | Revoke a system certificate |
| `just renew NAME` | Revoke and re-issue |
| `just verify NAME` | Show subject, SANs, dates and verify the chain |
| `just list` | List every issued cert with expiry and status |
| `just trust` | Install the CA into the system **and** browser trust stores |
| `just trust-system` | System trust store only (curl, python, wget) - uses `sudo` |
| `just trust-browsers` | Browser (NSS) trust stores only |
| `just trust-status` | Show where the CA is currently trusted |
| `just trust-help` | Print copy-paste instructions for trusting it by hand |
| `just untrust` | Remove the CA from both trust stores |
| `just uninstall` | Untrust **and** delete the generated CA in `./output` |
| `just clean` | Delete `./output`, leaving the trust stores alone |
| `just lint` | Run every pre-commit hook over the tree |
| `just commit` | Write a Conventional Commit interactively |

## Setup detail

- Copy `.env.example` -> `.env` (`just init`) and update the values at the top of the file: the three private key passwords and the OpenSSL cert subject values.
- `just ca` generates the Root CA, the Intermediate CA and the Root-Intermediate chain into `./output`.
    - It **deletes `./output` first**, which takes every previously issued system cert with it, so it prompts for confirmation when a CA already exists. `just ca --force` skips the prompt.
- `just new-system NAME` copies `configs/systems/example.ext` to `configs/systems/NAME.ext` with the name substituted. Edit the `[alt_names]` block so the DNS and IP entries match the host:

    ```
    [alt_names]
    DNS.1 = localhost
    DNS.2 = server01
    DNS.3 = server01.local
    DNS.4 = server01.internal
    IP.1 = 127.0.0.1
    IP.2 = 10.10.10.50
    ```

- `just cert NAME` issues the certificate. Copy these two files to the service:
    - `./output/systems/NAME/NAME-no-pass.key.pem` - the private key. The passworded `NAME.key.pem` alongside it needs a password at load time and is not suitable for most services.
    - `./output/systems/NAME/NAME.fullchain.cert.pem` - **point services at this**, not the bare `NAME.cert.pem`. Clients only trust the Root/Intermediate CA, so the server has to send the intermediate on the wire. Browsers hide a missing intermediate by fetching it themselves (AIA chasing), but curl, openssl and python requests deliberately do not, and fail with `unable to get local issuer certificate`. The bare `NAME.cert.pem` is still generated for the rare service that wants the leaf and chain as separate inputs.
- To replace a cert: `just renew NAME`.

## Trusting the CA

Two separate trust stores need the CA installed, and neither reads the other:

- **Browsers** (Chrome, Chromium, Firefox) use their own NSS databases - `~/.pki/nssdb` for Chrome, one per profile for Firefox (including the snap and flatpak locations).
- **CLI tools** (curl, openssl, wget, python) use the OS trust store.

`just trust` does both. `just trust-status` shows where things stand:

```
System trust store (debian):
  TRUSTED

Browser (NSS) trust stores:
  TRUSTED      sql:/home/you/.pki/nssdb
  TRUSTED      sql:/home/you/.mozilla/firefox/xxxxxxxx.default
```

Restart any running browser after installing.

If `certutil` is missing, the script says exactly which package to install for your distro and stops without touching anything. `just trust-help` prints the manual alternative:

```
Firefox   Settings -> Privacy & Security -> Certificates -> View Certificates ->
          Authorities -> Import -> ./output/root/certs/ca.cert.pem
          and tick "Trust this CA to identify websites".
Chrome    Settings -> Privacy and security -> Security -> Manage certificates ->
          Authorities -> Import, same file.
```

Until the CA is trusted you can always pass it explicitly:

```sh
curl --cacert ./output/root/certs/ca.cert.pem https://server01.local/
```

### Why the root and not the chain

Import the **Root** CA (`./output/root/certs/ca.cert.pem`), never `ca-chain.cert.pem`. Most import paths - Chrome's certificate manager, `certutil`, and `update-ca-certificates`' hashing step - only read the **first** certificate in a multi-cert file. Importing the chain therefore installs the intermediate and silently leaves you without the trust anchor. The root is what matters: with it installed, and services serving the fullchain file, nothing else is needed.

For the same reason the system store gets the root and the intermediate as two separate `.crt` files (`local-ca-root.crt`, `local-ca-intermediate.crt`). Two more `update-ca-certificates` traps the script handles for you:

- It only ingests files under `/usr/local/share/ca-certificates/` ending in `.crt`. A `.pem` file is silently ignored - no warning, it just never becomes trusted.
- It lives in `/usr/sbin`, which is not on a regular user's `PATH` on Debian, so `command -v update-ca-certificates` finds nothing on a machine that plainly has it.

Fedora/RHEL (`update-ca-trust`) and Arch (`trust extract-compat`) are supported too; the flavour is detected automatically.

## Uninstalling

```sh
just untrust      # remove the CA from both trust stores, keep ./output
just uninstall    # remove it from both trust stores AND delete ./output
```

`just uninstall` prompts before doing anything. Note that certificates already deployed to your services become untrusted, and once `./output` is gone they can no longer be revoked - remove them from those hosts too.

## Development

```sh
just setup     # install the git hooks
just lint      # run every hook over the whole tree
just commit    # write a Conventional Commit interactively
```

Commits follow [Conventional Commits](https://www.conventionalcommits.org/), enforced by [commitizen](https://commitizen-tools.github.io/commitizen/) at `commit-msg` time and again over the whole range at `pre-push`, so a message committed with `--no-verify` still cannot reach the remote.

Nothing generated by this repo should ever be committed. Three layers guard that:

- `.gitignore` covers `output/`, `.env`, loose key material and the per-host `configs/systems/*.ext` files (only `example.ext` is tracked).
- [gitleaks](https://github.com/gitleaks/gitleaks), `detect-private-key` and `detect-aws-credentials` scan staged content.
- `hooks/forbid-secret-files.sh` blocks by **path** - keys, CSRs, certs, `private/` directories and `.env` - which catches the cases content scanning misses, like a key renamed or copied out of the ignored directory during debugging.

Whitespace is normalised by `trailing-whitespace`, `end-of-file-fixer`, `mixed-line-ending`, the CRLF hooks and `forbid-tabs`, with the shared rules in `.editorconfig`. Shell is linted with `shellcheck`.

## Other Resources
Tools and resources you should check before using the scripts in this repo.

- https://github.com/pasuder/simple-ca-manager
- https://arminreiter.com/2022/01/create-your-own-certificate-authority-ca-using-openssl/
- https://github.com/jtyers/openssl-util
- https://smallstep.com/certificates/
    - https://github.com/smallstep/certificates
- https://letsencrypt.org/docs/certificates-for-localhost/
