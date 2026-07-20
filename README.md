# Harmony Platform

Production ownership for the shared Harmony VPS stack.

- Public API: `https://harmony-resolver.duckdns.org`
- Resolver: `/resolver/*`
- Harmony Cloud: `/cloud/*`
- Persistent volumes retain the existing `harmony-resolver_*` names during migration.
- Service repositories publish immutable images; this repository alone deploys production.

Runtime secrets live in `/etc/harmony-platform/harmony-platform.env` and GitHub's `production`
Environment. They are never committed.

Run the state-preserving cutover and bootstrap once, interactively as a VPS administrator. Cutover
creates a PostgreSQL dump, removes the old Harmony containers and checkouts, and preserves all named
volumes plus the legacy credentials required to open them. The Platform Compose file adopts the
existing PostgreSQL, MinIO, Valkey, RabbitMQ and observability volumes by their current names.
Bootstrap then installs Docker when needed, creates or preserves the restricted deploy account,
copies the compatible legacy credentials, generates new Cloud secrets and TLS material, and installs
the root-owned deploy wrapper.

The GitHub `production` Environment requires only `VPS_HOST`, `VPS_SSH_KEY`, `VPS_IPV4` and
`DUCKDNS_TOKEN`. Resolver and Cloud repositories additionally need `PLATFORM_DISPATCH_TOKEN`.

After bootstrap, publishing, DNS updates, deployment, health checks and image rollback use only the
restricted `deploy` key. The deploy user cannot modify the root-owned checkout or deployment
command; it may only invoke the root-owned wrapper with validated Harmony image references.

Each deployment creates or rotates a non-administrator RabbitMQ `downloader` user with access only
to `harmony.ingest.jobs`. After the first successful deployment, obtain its local downloader
settings without opening the root-owned environment file:

```bash
sudo bash /opt/harmony-platform/scripts/show-downloader-config.sh
```
