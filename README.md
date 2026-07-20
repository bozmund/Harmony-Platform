# Harmony Platform

Production ownership for the shared Harmony VPS stack.

- Public API: `https://harmony-resolver.duckdns.org`
- Resolver: `/resolver/*`
- Harmony Cloud: `/cloud/*`
- Persistent volumes retain the existing `harmony-resolver_*` names during migration.
- Service repositories publish immutable images; this repository alone deploys production.

Runtime secrets live in `/etc/harmony-platform/harmony-platform.env` and GitHub's `production`
Environment. They are never committed.

One VPS bootstrap is required after cloning the Platform repository:

```bash
sudo bash /opt/harmony-platform/scripts/bootstrap.sh
```

Fill the three Auth0 values in the generated environment file and add the documented GitHub
Environment secrets. After that, service publishing, DNS update, deployment, health checks and
image rollback are performed by GitHub Actions.

Required `production` Environment secrets are `VPS_HOST`, `VPS_SSH_KEY`, `VPS_IPV4` and
`DUCKDNS_TOKEN`. Resolver and Cloud repositories additionally need `PLATFORM_DISPATCH_TOKEN`.
