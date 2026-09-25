"""Create the single POC tenant using the mounted OpenPGP key."""

from __future__ import annotations

import os
import re

from provisioning.authz.manager import AuthzManager
from provisioning.connections.config import TenantConfig


tenant = os.environ["POC_TENANT"]
fingerprint = os.environ["SOPS_PGP_FINGERPRINT"]
logical_namespace = "marcopolo"

config = TenantConfig(tenant, logical_namespace)
config.ensure_directories()

sops_config = config.paths.sops_config
creation_rule = (
    "creation_rules:\n"
    f"  - path_regex: '{re.escape(tenant)}\\.(exporters\\.)?secrets\\.yaml$'\n"
    f"    pgp: {fingerprint}\n"
)
if sops_config.exists():
    existing_rule = sops_config.read_text(encoding="utf-8")
    if f"pgp: {fingerprint}" not in existing_rule:
        raise RuntimeError("tenant SOPS configuration uses a different OpenPGP key")
else:
    sops_config.write_text(creation_rule, encoding="utf-8")
    os.chmod(sops_config, 0o600)

if config.paths.secrets.exists():
    config.read_secrets()
else:
    config.write_secrets({"DV_CUSTOMER": tenant})

authz = AuthzManager(tenant, config.paths.policy)
authz.ensure_default_policies()
