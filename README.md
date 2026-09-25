# Marcopolo local POC

Run Marcopolo on an Apple Silicon Mac that already uses Docker through Colima.
The installer downloads verified arm64 image archives from this repository's
public GitHub Release, imports them into Colima K3s, and exposes Marcopolo at
http://localhost:8000.

The POC stores its state in the Colima VM. It does not mount the Mac filesystem,
pull from a container registry, require AWS access, or contain Marcopolo source
code.

## Before installation

The GitHub Release must provide arm64 archives for Marcopolo API, mproxy, and
the Marcopolo user image. Marcopolo maintains their exact URLs and SHA-256
values in the tracked `config/release.env` file.

Prashanth needs the POC private OpenPGP key and its passphrase through an
approved secure channel. Neither belongs in Git.

Colima must be allowed to enable K3s and download its own system components.
If that requires a prolonged IT approval, use the GCP environment instead.

## Install

```bash
cp config/customer.env.template config/customer.env
# Set PGP_PRIVATE_KEY_FILE and PGP_PASSPHRASE_FILE to local owner-only files.

./scripts/bootstrap-kubernetes.sh
./scripts/preflight.sh
./scripts/deploy.sh
./scripts/port-forward.sh
```

Keep `port-forward.sh` running while using Marcopolo. It exposes only
`localhost:8000`.

## Verify and operate

```bash
./scripts/status.sh
./scripts/logs.sh marcopolo
./scripts/logs.sh mproxy
./scripts/test-executor-network.sh data-source.example.com 443
```

The network test checks access from an executor pod. Test each data-source host
and port before configuring its credentials.

To remove the POC and all state in the Colima VM:

```bash
./scripts/teardown.sh
```

## Local key handling

Keep the private key and passphrase outside the repository with owner-only
permissions. Deployment copies them into Kubernetes Secrets in the local
Colima VM for API and mproxy startup. The executor never receives the key.
