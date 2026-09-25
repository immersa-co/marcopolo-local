# Marcopolo local POC

Apple Silicon deployment on Colima Kubernetes. Images come from this repository's GitHub Release. Open Marcopolo at http://localhost:8000.

## Requirements

- Colima and Docker CLI
- GitHub Release and data-source access
- PGP private key and passphrase files

## Run

```bash
cp config/customer.env.template config/customer.env
```

Set the two local file paths in `config/customer.env`:

```dotenv
PGP_PRIVATE_KEY_FILE=/path/to/private.asc
PGP_PASSPHRASE_FILE=/path/to/passphrase.txt
```

```bash
./scripts/bootstrap-kubernetes.sh
./scripts/deploy.sh
./scripts/port-forward.sh
```

## Operations

```bash
./scripts/status.sh
./scripts/logs.sh marcopolo
./scripts/logs.sh mproxy
./scripts/test-executor-network.sh host.example.com 443
./scripts/teardown.sh
```

Keep the private key and passphrase outside the repository. Do not edit `config/release.env`.
