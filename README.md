# dns-failover

Active-passive DNS failover for www.vmkpi-mis.in using Cloudflare DNS + GitHub Actions.

- `failover.py` - health-checks the primary and backup public IPs and updates the Cloudflare A record.
- `.github/workflows/failover.yml` - runs the check every 5 minutes.
- `keepalive.sh` - periodic commit so GitHub does not disable the scheduled workflow after 60 days of inactivity.

Secrets (`CF_API_TOKEN`, `CF_ZONE_ID`) live only in GitHub Actions Secrets, never in the repo.
