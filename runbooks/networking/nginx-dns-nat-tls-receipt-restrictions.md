# Nginx edge delivery: DNS, NAT, TLS, and restricted receipt downloads

> Sanitized UAT case study and reusable diagnostic runbook. Hostnames, addresses, customer data, private certificates, and authentication material are omitted. The operational routing and access-control checks below were verified; **receipt-specific signed-token authorization is a separate, unverified security gate**.

## Situation

Three HTTPS virtual hosts were provisioned behind a shared reverse proxy for an API gateway, a receipt store, and a webview. The receipt backend used an HTTP-accessible object-store filer. Initial public testing failed even though the receipt worked on the private network. Later, exposing the entire Filer UI had to be replaced with read-only single-file receipt retrieval.

## Architecture (illustrative; not actual deployment addresses)

```text
Public DNS A records (multiple hostnames -> one public IP)
                     |
           Firewall / TCP 443 DNAT
                     |
           Nginx reverse proxy
                TLS + SNI
         +-----------+-----------+
         |           |           |
      Gateway     Receipt       Webview
     private      private       private
      backend   object store    backend
                  /invoices
```

Each domain has a separate Nginx `server_name`. Multiple A records can use the **same public IP** when the firewall forwards port 443 to the same Nginx instance. The HTTP Host header/SNI selects the virtual host; separate public addresses are not required for each hostname. Confirm ownership, NAT destination, return path, and existing virtual hosts before changing DNS.

## Evidence and sequence

| Boundary | Check | Verified finding |
|---|---|---|
| Certificate | `openssl x509 ... -checkhost` | An existing wildcard certificate covered a **different parent domain** than the originally proposed names. Corrected hostnames matched the certificate. |
| Nginx | `nginx -t`, reload and localhost `curl --resolve` | Proxy configuration passed and gateway/receipt returned HTTP 200 locally. |
| External DNS | `dig @1.1.1.1`, `dig @8.8.8.8` | Initially only one hostname returned an A record. The other two lookups used different names than the DNS team's entries (a spelling difference and a missing environment suffix). |
| Public transport | `curl --resolve hostname:443:PUBLIC_IP` | An originally proposed public IP timed out, independent of DNS. Host firewall already allowed port 443. The upstream routing/NAT path needed independent verification. |
| Application | Direct backend URL | Receipt object-store UI responded internally. Webview backend had not yet started, so its initial 502 was an expected application-readiness issue. |
| Corrected DNS + ingress | External HTTPS request | A receipt was rendered successfully through the corrected public domain. |
| Access controls | Requests to folders, real files, missing files, write methods | Directory paths returned 403, a known existing file returned 200, a missing file returned 404, and POST/PUT/DELETE/PATCH/OPTIONS to a disposable nonexistent name returned 403. |

**Do not overclaim root cause:** the public-IP timeout was observed; the exact upstream firewall/NAT change was not independently captured. The corrected DNS names and public receipt retrieval were verified separately.

## 1. Distinguish DNS from TCP reachability

Resolve every **exact** hostname, including environment suffixes and spelling:

```bash
for h in api.uat.example.com receipt.uat.example.com webview.uat.example.com; do
  echo "=== $h ==="
  dig @1.1.1.1 +time=3 +tries=1 +short A "$h"
  dig @8.8.8.8 +time=3 +tries=1 +short A "$h"
done
```

Empty output does not always mean NXDOMAIN: inspect `dig` status/response details, resolver timeouts, and authoritative answers. A shell alias replacing `grep` with `rg` can also invalidate parsing logic; keep this first check free of parsing pipelines.

Force a public TCP/TLS test without relying on DNS:

```bash
curl -Iv --connect-timeout 8 \
  --resolve receipt.uat.example.com:443:203.0.113.10 \
  https://receipt.uat.example.com/
```

Replace the documentation-only address with the *confirmed assigned* public IP. If the test times out from an internal client, repeat from a genuinely external network: hairpin NAT may be unavailable.

## 2. Verify which Nginx host receives traffic

```bash
sudo nginx -t
sudo ss -lntp | grep ':443'
sudo ufw status verbose    # if UFW is in use
```

Check the virtual host directly, bypassing external routing:

```bash
curl -Iv \
  --resolve receipt.uat.example.com:443:127.0.0.1 \
  https://receipt.uat.example.com/
```

Start a **simultaneous** packet capture on the Nginx host, then initiate the external `curl` while capture is running:

```bash
sudo timeout 30 tcpdump -ni <ingress-interface> 'tcp port 443'
```

No SYN observed during the known test window suggests the request does not reach the interface (subject to capture interface, NAT topology and filters). SYNs without successful handshake call for return-path, host firewall and TLS diagnostics. Stopping `tcpdump` *before* the external request proves nothing.

## 3. Verify TLS against the actual hostname

```bash
openssl x509 -in /path/to/fullchain.pem \
  -noout -subject -dates -ext subjectAltName

openssl x509 -in /path/to/fullchain.pem \
  -noout -checkhost receipt.uat.example.com
```

A certificate for `*.one-domain.example` does not validate a host under `*.another-domain.example`. Also verify that the certificate's public key matches the configured private key **without printing or uploading private material**. Record the renewal date.

`server_tokens off;` under the main `http` block hides the Nginx version from standard response headers/error pages. It does not eliminate the `Server: nginx` header or replace security hardening.

## 4. Keep Nginx modular and avoid accidental URI rewrites

Prefer per-service files in `conf.d/` plus reviewed shared snippets. Direct backends are acceptable for a single upstream; named `upstream` blocks help when pooling or tuning multiple instances.

Caution: these are **different**:

```nginx
# Preserve original URI and query string unless separately rewritten.
proxy_pass http://receipt_backend;

# In a prefix location, replacing the matched URI can produce
# surprising paths when slashes are missing.
proxy_pass http://receipt_backend/invoices;
```

Test path mapping with a known file and a nonexistent file before publishing a route. When using `proxy_pass http://receipt_backend$uri;` (a variable), the original query string is **not automatically forwarded**. This matters if a design relies on a `?token=` argument.

## 5. Read-only file-path restrictions

The following *illustrative* edge pattern allows a direct file under `/invoices/` and denies other paths. It is **not production-safe by itself** because it has no per-file authorization:

```nginx
# Example within a dedicated receipt server block.
error_page 403 /403.html;

location = /403.html {
    internal;
    alias /var/www/nginx-errors/403.html;
}

location / {
    return 403;
}

location ~ ^/invoices/[A-Za-z0-9][A-Za-z0-9._-]*$ {
    limit_except GET HEAD { deny all; }

    # Backend receives a normalized path; query parameters are omitted.
    # A separate verified authorization check is mandatory before
    # exposing financial documents to untrusted clients.
    proxy_pass http://receipt_backend$uri;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Adapt the filename policy to actual object keys and ensure it does not accidentally block valid receipt IDs (which may lack an extension). Do not expose the Filer's browsing/upload UI publicly. Restrict test access by trusted source ranges while authorization is still being implemented.

After backing up the configuration, apply changes with `nginx -t && systemctl reload nginx`. The custom page can be served with `error_page 403` and an internal location; `server_tokens off;` removes version leakage.

## 6. Negative and positive tests

For a disposable **nonexistent** name, run:

```bash
BASE='https://receipt.uat.example.com'
PATH_TO_TEST='/invoices/nginx-security-smoke-test-nonexistent'
for method in POST PUT DELETE PATCH OPTIONS; do
  curl -sS -o /dev/null -w "$method: %{http_code}\n" \
    -X "$method" "$BASE$PATH_TO_TEST"
done
curl -sS -o /dev/null -w "directory: %{http_code}\n" "$BASE/invoices/"
curl -sS -o /dev/null -w "missing file: %{http_code}\n" "$BASE$PATH_TO_TEST"
```

Expected: directory and modification methods 403; nonexistent permitted-path filename typically 404. Separately request a known **synthetic/test** file via GET and HEAD and verify response content/status. Avoid uploading real receipt PDFs, customer identifiers or snapshots to public repositories.

Observed UAT results: read-only methods GET/HEAD on a known file returned 200; all five tested mutation/other methods returned 403; nonexistent file returned 404.

## 7. Security acceptance gate: signed URL enforcement

**A gateway *generating* `/invoices/<id>?token=<signed-token>` does not prove the receipt edge validates the token.** An unrestricted receipt route may still return 200 without it, and using `proxy_pass ...$uri` drops query parameters before reaching the backend.

Before closing the security task, require a verifier at the trusted boundary (for example, Nginx `auth_request` calling a private gateway endpoint) that validates:

- Token signature, expiration, and intended receipt ID/path (and intended principal/audience where applicable).
- Missing, malformed, expired, tampered, and cross-receipt tokens are all denied.
- The Gateway checks user-to-receipt authorization **before issuing** the link.
- Upstream object storage cannot be reached directly from untrusted networks.
- URL tokens are redacted from access logs, traces, analytics and error reporting; avoid default `$request` logs leaking query strings.
- GET and HEAD authorization semantics are explicit; access is not assumed to be single-use. Replay prevention requires stateful token tracking if mandated.

Acceptance tests: missing token -> 401/403; invalid token -> 401/403; expired token -> 401/403; token for a different receipt -> 401/403; valid token -> 200; folder/mutation restrictions continue to return 403. Test all from outside the trusted network, then monitor backend and reverse-proxy logs.

**State at documentation time:** Edge networking, TLS, restricted path routing and method filtering validated. Cryptographic token verification / per-receipt authorization **not verified**; do not mark the endpoint approved for unrestricted financial-document access solely on the above routing tests.

## Rollback and operational closure

Keep a validated copy of the prior Nginx file, restore it if reload validation fails, and use `nginx -t` before every reload. Retest local vhost, external DNS, external HTTPS and a permitted synthetic file after DNS/NAT changes. Preserve sanitized command outputs in change records; keep raw business data and secrets in authorized internal systems only.

### Takeaways

1. `nginx -t` proves syntax, not reachability or authentication.
2. DNS spelling and environment suffixes can make two teams report contradictory but internally correct results.
3. One public IP can front many TLS virtual hosts.
4. TCP reachability, TLS validity, application health, and document-level authorization are separate gates.
5. Existing file retrieval and 403-forbidden directory behavior do not, by themselves, prove signed URL security.
