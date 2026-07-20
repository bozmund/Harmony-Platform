# Harmony Platform Agent Guide

- This repository owns production infrastructure, ingress, shared stateful services, and deployment.
- Preserve named production volumes and take a backup before every migration or Compose rollout.
- Never commit runtime credentials, certificate private keys, Auth0 secrets, DuckDNS tokens, or SSH keys.
- Production changes must flow through GitHub Actions; scripts must be idempotent and non-interactive.
- Do not run Git state-changing commands without explicit authorization for that exact operation.
- Save accepted plans under `plans/` and index them in `plans/index.md`.
