# State-preserving Harmony cutover and automated deploy

## Decision

Run the initial Harmony cutover and bootstrap once, interactively as a VPS administrator. Preserve
the existing databases and object storage by adopting the current named volumes and transferring
their matching credentials. After that trust boundary is established, every deployment, DNS update,
migration, health check and rollback is automated through GitHub Actions.

## Safety boundary

The cutover removes only explicitly named disposable Harmony resources:

- Compose containers named by the `harmony-resolver` or `harmony-platform` labels;
- `/opt/harmony-resolver`, `/opt/harmony-platform`, and Harmony-specific systemd/sudoers/wrapper
  files.

It preserves all named Harmony volumes, `/etc/harmony-resolver` legacy credentials, PostgreSQL
backups, Ubuntu, SSH access, unrelated containers/volumes, home directories, firewall configuration,
and unrelated application data. Cutover requires explicit confirmation and all recursive path
removal validates the resolved absolute target first.

## Initial administrator bootstrap

1. Connect to the VPS with the existing administrator SSH access.
2. Run the cutover script with the explicit `PREPARE-HARMONY-CUTOVER` confirmation.
3. Create and verify a PostgreSQL dump before stopping the legacy service.
4. Preserve every named volume and the legacy environment containing its matching credentials.
5. Clone the root-owned Platform checkout.
6. Run bootstrap as root.
7. Bootstrap installs Git, Docker Engine, Compose and required host firewall rules.
8. Bootstrap creates or preserves the restricted `deploy` account.
9. Bootstrap imports compatible legacy credentials and generates new Cloud/Grafana/TLS secrets.
10. The administrator supplies the three Auth0 runtime values in the root-owned environment.
11. Bootstrap installs a root-owned validated deploy wrapper and exact sudo rule for that wrapper.
12. A normal Platform deploy Action pulls images, starts the stack, runs migrations, creates the
    restricted downloader RabbitMQ user, and executes HTTPS health checks.

Routine deployments use only the restricted deploy key. Harmony Music is a separate frontend client
and is outside this server bootstrap and deployment scope.

## Required GitHub inputs

- Platform: `VPS_HOST`, `VPS_IPV4`, `DUCKDNS_TOKEN`, `VPS_SSH_KEY`
- Resolver and Cloud: `PLATFORM_DISPATCH_TOKEN`

The three Auth0 runtime values are stored only in `/etc/harmony-platform/harmony-platform.env`.

No runtime credential, private key or token is committed to Git.
