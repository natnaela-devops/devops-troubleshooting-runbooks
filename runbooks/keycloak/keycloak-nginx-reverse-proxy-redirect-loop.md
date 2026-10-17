# Keycloak behind Nginx: redirect loops, wrong scheme, and proxy-header failures

This runbook covers a common failure pattern when Keycloak is published through an Nginx reverse proxy: repeated `302` redirects, links generated with the wrong `http`/`https` scheme, admin-console failures, or `403` origin-check errors.

> Examples are intentionally generic. Replace hostnames, ports, and trusted proxy ranges with values appropriate to the environment.

## Typical symptoms

- Browser repeatedly redirects between the same Keycloak URLs.
- The public URL is HTTPS, but Keycloak generates HTTP redirects.
- Admin Console loads partially or fails origin checks.
- Requests through Nginx fail while direct backend access succeeds.
- Keycloak logs show hostname/origin-related failures.

## 1. Confirm the TLS topology first

Identify which model is actually deployed:

- **Edge termination:** client -> HTTPS -> Nginx -> HTTP -> Keycloak
- **Re-encryption:** client -> HTTPS -> Nginx -> HTTPS -> Keycloak
- **TLS passthrough:** Nginx/LB does not terminate TLS

Do not mix configuration from these models. In particular, proxy headers are appropriate when the proxy terminates or re-encrypts HTTP traffic, but not for TLS passthrough.

## 2. Use current Keycloak hostname settings

For modern Keycloak releases, prefer hostname v2 settings such as:

```bash
KC_HOSTNAME=https://sso.example.com
KC_PROXY_HEADERS=xforwarded
```

If Nginx terminates TLS and talks HTTP to Keycloak, HTTP must also be enabled on the Keycloak side:

```bash
KC_HTTP_ENABLED=true
```

If the admin console is intentionally exposed on a different hostname, use:

```bash
KC_HOSTNAME_ADMIN=https://sso-admin.example.com
```

Avoid copying legacy examples that rely on older hostname variables without first checking the installed Keycloak version.

## 3. Make Nginx overwrite forwarded headers

A minimal reverse-proxy location should explicitly set the externally visible request information:

```nginx
location / {
    proxy_pass http://keycloak_backend;

    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
}
```

The important point is not merely that the headers exist. The trusted reverse proxy should set or overwrite them so clients cannot supply forged values that Keycloak later trusts.

## 4. Restrict which proxies Keycloak trusts

Where supported by the deployed Keycloak version, restrict trusted proxy addresses instead of accepting forwarded identity information from arbitrary sources.

Example concept:

```bash
KC_PROXY_HEADERS=xforwarded
KC_PROXY_TRUSTED_ADDRESSES=10.0.0.0/24
```

Use the actual reverse-proxy subnet, not a broad placeholder range.

## 5. Validate each layer independently

### Backend reachability

From the Nginx host:

```bash
curl -I http://127.0.0.1:8080/
ss -lntp | grep 8080
```

### Public redirect behavior

```bash
curl -kIL https://sso.example.com/
```

Look for:

- repeated redirects to the same URL;
- redirects from HTTPS back to HTTP;
- unexpected hostnames or ports;
- an incorrect context path.

### Nginx effective configuration

```bash
nginx -t
nginx -T
```

### Keycloak runtime configuration

Inspect the systemd environment, container environment, or deployment manifest that is actually running. Do not assume the source `.env` or unit file matches the active process.

## 6. Context-path mismatches

If the public path is different from Keycloak's internal path, align it deliberately. Valid approaches include:

- exposing Keycloak at the same path internally and externally;
- using a full public hostname URL that contains the intended path;
- configuring the reverse proxy and Keycloak relative path consistently.

A path mismatch can look like an authentication problem even when credentials and TLS are correct.

## 7. Recovery sequence

1. Back up Nginx and Keycloak configuration.
2. Confirm edge/re-encrypt/passthrough topology.
3. Correct Keycloak hostname and proxy-header settings.
4. Correct Nginx forwarded headers.
5. Run `nginx -t` before reload.
6. Restart or reload only the component whose runtime configuration changed.
7. Validate with `curl -IL` before testing through the application.
8. Confirm login, logout, admin-console access, and application callback URLs.

## Root-cause pattern

The failure is usually not "SSL is broken." It is a disagreement between the externally visible URL and what Keycloak believes the original request looked like. Troubleshooting should therefore compare scheme, host, port, path, and forwarded headers across every hop before changing authentication settings.
