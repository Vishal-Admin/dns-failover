#!/usr/bin/env python3
"""Cloudflare DNS active-passive failover (primary/backup A record).

Env vars:
  CF_API_TOKEN   Cloudflare API token (Zone > DNS > Edit, only for this zone)
  CF_ZONE_ID     Cloudflare Zone ID of the domain
  RECORD_NAMES   comma list of A records to manage, e.g. "vmkpi-mis.in,www.vmkpi-mis.in"
  PRIMARY_IP     default 14.139.121.234
  BACKUP_IP      default 27.111.73.30
  CHECK_HOST     hostname sent as SNI/Host, default www.vmkpi-mis.in
  CHECK_PATH     default /
Flags: --check-only (no Cloudflare calls), --dry-run (log, don't change DNS)
Exit code 1 if both IPs are down or a DNS change failed (so GitHub emails you).
"""
import json, os, socket, ssl, sys, time, urllib.request, urllib.error

PRIMARY = os.environ.get("PRIMARY_IP", "14.139.121.234")
BACKUP = os.environ.get("BACKUP_IP", "27.111.73.30")
HOST = os.environ.get("CHECK_HOST", "www.vmkpi-mis.in")
PATH = os.environ.get("CHECK_PATH", "/")
TTL = 60
TRIES, GAP = 3, 10  # 3 attempts, 10s apart, before an IP is called down
ERR = {}            # last error per IP, shown in GitHub annotations


def healthy(ip):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False          # server cert chain is incomplete; we test reachability
    ctx.verify_mode = ssl.CERT_NONE
    for i in range(TRIES):
        try:
            with socket.create_connection((ip, 443), timeout=8) as s:
                with ctx.wrap_socket(s, server_hostname=HOST) as t:
                    t.sendall(f"GET {PATH} HTTP/1.1\r\nHost: {HOST}\r\nConnection: close\r\n\r\n".encode())
                    line = t.recv(64).split(b"\r\n")[0].decode(errors="ignore")
                    code = int(line.split()[1])
                    if code < 500:
                        return True
                    ERR[ip] = f"HTTP {code}"
                    print(f"  {ip}: HTTP {code}")
        except Exception as e:
            ERR[ip] = f"{type(e).__name__}: {e}"
            print(f"  {ip}: attempt {i+1} failed: {e}")
        if i < TRIES - 1:
            time.sleep(GAP)
    return False


def cf(method, path, body=None):
    req = urllib.request.Request(
        "https://api.cloudflare.com/client/v4" + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Authorization": "Bearer " + os.environ["CF_API_TOKEN"],
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Cloudflare API error {e.code}: {e.read().decode()[:500]}")


def set_record(zone, name, ip, dry):
    recs = cf("GET", f"/zones/{zone}/dns_records?type=A&name={name}")["result"]
    if len(recs) == 1 and recs[0]["content"] == ip and not recs[0]["proxied"]:
        print(f"  {name}: already {ip}, no change")
        return
    print(f"  {name}: {[r['content'] for r in recs] or 'none'} -> {ip}")
    if dry:
        return
    body = {"type": "A", "name": name, "content": ip, "ttl": TTL, "proxied": False}
    # keep the record that already holds the target IP (if any), delete the others FIRST
    # (Cloudflare refuses to create/update a duplicate of an existing identical record)
    keep = next((r for r in recs if r["content"] == ip), recs[0] if recs else None)
    for extra in recs:
        if keep is None or extra["id"] != keep["id"]:
            cf("DELETE", f"/zones/{zone}/dns_records/{extra['id']}")
    if keep is None:
        cf("POST", f"/zones/{zone}/dns_records", body)
    else:
        cf("PUT", f"/zones/{zone}/dns_records/{keep['id']}", body)


def main():
    check_only, dry = "--check-only" in sys.argv, "--dry-run" in sys.argv
    print(f"Checking primary {PRIMARY} ...")
    p_ok = healthy(PRIMARY)
    print(f"  primary: {'UP' if p_ok else 'DOWN'}")
    if not p_ok:
        print(f"::warning::primary {PRIMARY} DOWN from GitHub runner: {ERR.get(PRIMARY)}")
    b_ok = None
    if not p_ok or check_only:
        print(f"Checking backup {BACKUP} ...")
        b_ok = healthy(BACKUP)
        print(f"  backup: {'UP' if b_ok else 'DOWN'}")
    if check_only:
        return 0
    if p_ok:
        target = PRIMARY
    elif b_ok:
        target = BACKUP
    else:
        print(f"::error::BOTH links DOWN from GitHub runner - DNS unchanged. primary={ERR.get(PRIMARY)} backup={ERR.get(BACKUP)}")
        return 1
    print(f"Target IP: {target}")
    for name in [n.strip() for n in os.environ["RECORD_NAMES"].split(",") if n.strip()]:
        set_record(os.environ["CF_ZONE_ID"], name, target, dry)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit as e:
        if isinstance(e.code, str):
            print("::error::" + e.code)
            sys.exit(1)
        raise
    except Exception as e:
        print(f"::error::{type(e).__name__}: {e}")
        sys.exit(1)
