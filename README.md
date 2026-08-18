# Harmony Platform

Production ownership for the shared Harmony VPS stack.

- Public API: `https://harmony-resolver.duckdns.org`
- Resolver: `/resolver/*`
- Harmony Cloud: `/cloud/*`
- Persistent volumes retain the existing `harmony-resolver_*` names during migration.
- Service repositories publish immutable images; this repository alone deploys production.

Runtime secrets live in `/etc/harmony-platform/harmony-platform.env` and GitHub's `production`
Environment. They are never committed.

## SSH-only Resolver administration

The failed-track retry console is never public. Create an Auth0 **Single Page Application** client
(or reuse an existing public client that already requests tokens for `https://harmony-resolver`),
grant your administrator role the `resolver:admin` permission for that API, and configure these
Auth0 URLs on the client:

- Allowed callback: `http://localhost:8081/admin/retries`
- Allowed logout: `http://localhost:8081/admin/retries`
- Allowed web origin: `http://localhost:8081`

Set that client's public id as the `ADMIN_AUTH0_CLIENT_ID` repository secret in GitHub's
`production` Environment. `deploy.yml` passes it to `harmony-platform-deploy` on every deploy, and
`deploy.sh` reasserts it into the root-owned runtime environment file — set once in GitHub, never a
manual edit on the box again. Leaving the secret unset leaves whatever is already on disk untouched,
so this is safe to add after the fact.

Access it only through the VPS tunnel:

```powershell
ssh -i .\Downloads\ssh-key-2026-07-16.key -L 8081:127.0.0.1:8081 ubuntu@92.5.15.68
```

Then open `http://localhost:8081/admin/retries`. Nginx returns 404 for the equivalent public
`/resolver/admin/*` paths, so an Auth0 role alone is not enough to reach the console.

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
