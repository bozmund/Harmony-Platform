# Harmony trajna pohrana, Cloud backup i prefetch

Potpuni prihvaćeni plan identičan je canonical planu u Harmony Resolver repozitoriju:
`C:\MyRepositories\Harmony-Resolver\plans\2026-07-20_0111_harmony_cloud_durable_media.md`.

## Harmony Platform scope

- Jedini production owner Composea, Nginxa/Caddyja, certifikata, PostgreSQLa, MinIOa, Valkeyja, RabbitMQa i observabilityja.
- Zajednički postojeći hostname `harmony-resolver.duckdns.org` s rutama `/resolver/*` i `/cloud/*`.
- Očuvanje postojećih `harmony-resolver_*` volumena i automatski backup baza prije cutovera.
- RabbitMQ TLS cert vrijedi za novi hostname i downloader koristi port 5671.
- Resolver i Cloud objavljuju immutable image te dispatchaju Platform.
- Samo Platform action radi SSH deploy, migracije, health check i rollback.
- DuckDNS IP i TLS obnavljaju se automatizirano.

## Zajedničke granice i rollout

- Resolver trajno zadržava verificirani globalni audio; Cloud drži samo account sync podatke.
- Capacity pragovi su 45 GiB za prefetch, 48 GiB za backup i 50 GiB za urgentni ingest.
- Rollout: Platform i hostname, Resolver, Cloud, pa Music feature flag i smoke test.
- Jednokratno se postavljaju DuckDNS, Auth0, GHCR i VPS deploy tajne; daljnji deploy obavljaju Actions workflowi.
