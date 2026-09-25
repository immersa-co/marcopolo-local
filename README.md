# Marcopolo local POC

Apple Silicon deployment on Colima Kubernetes. Open Marcopolo at http://localhost:8000 and Grafana at http://localhost:3000.

## Requirements

- Colima and Docker CLI
- Access to this private repository
- PGP private key and passphrase files, supplied separately

## Run

```bash
git clone https://github.com/immersa-co/marcopolo-local.git
cd marcopolo-local
colima start --profile default
./scripts/bootstrap-kubernetes.sh
cp config/customer.env.template config/customer.env
mkdir -p ~/.marcopolo-poc
chmod 700 ~/.marcopolo-poc
```

Save the supplied private key as `~/.marcopolo-poc/private.asc` and its passphrase as `~/.marcopolo-poc/passphrase.txt`, then run:

```bash
chmod 600 ~/.marcopolo-poc/private.asc ~/.marcopolo-poc/passphrase.txt
```

Set `config/customer.env`:

```dotenv
PGP_PRIVATE_KEY_FILE=$HOME/.marcopolo-poc/private.asc
PGP_PASSPHRASE_FILE=$HOME/.marcopolo-poc/passphrase.txt
```

```bash
./scripts/deploy.sh
./scripts/port-forward.sh
```

Keep the key, passphrase, and token outside the repository. Do not edit `config/release.env`.
