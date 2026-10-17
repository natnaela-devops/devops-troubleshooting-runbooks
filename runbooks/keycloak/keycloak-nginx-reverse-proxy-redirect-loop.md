# Keycloak behind Nginx: redirect loops, wrong scheme, and proxy-header failures

This runbook documents a real Keycloak failure pattern behind an Nginx TLS-terminating reverse proxy: repeated `302` redirects, links generated with the wrong `http`/`https` scheme, or protocol mismatch errors.

> Examples are sanitized. Replace hostnames, ports, and trusted proxy ranges with values appropriate to the environment.

## Typical symptoms

- Browser repeatedly redirects between the same Keycloak URLs.
- The public URL is HTTPS, but Keycloak believes the request is HTTP.
- Requests through Nginx fail while direct backend access succeeds.
- Browser eventually reports `ERR_TOO_MANY_REDIRECTS`.

## Root cause pattern

The incident used edge TLS termination:

```text
Client --HTTPS--> Nginx --HTTP--> Keycloak
```

Nginx decrypted the request and forwarded it internally over HTTP. Keycloak did not initially receive/trust enough information to reconstruct the original external request, so it generated redirects based on the wrong scheme/host assumptions. That disagreement created the redirect loop.

## Nginx forwarded-header fix

The reverse proxy was configured to pass the original request context explicitly:

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

For modern configurations, also consider explicitly forwarding host/port where required:

```nginx
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Port $server_port;
```

The trusted proxy should overwrite these values rather than blindly preserving client-supplied forwarding headers.

## Keycloak configuration used in the incident

The deployed Keycloak version used the hostname/proxy variables available at that time:

```bash
KC_PROXY_HEADERS=xforwarded
KC_HOSTNAME_URL=https://sso.example.com
KC_HOSTNAME_STRICT_HTTPS=true
```

These values are retained here as the historical incident configuration. Newer Keycloak releases use hostname-v2 settings, so do not assume the exact variable names are portable across versions.

For modern releases, the equivalent pattern is typically closer to:

```bash
KC_HOSTNAME=https://sso.example.com
KC_PROXY_HEADERS=xforwarded
KC_HTTP_ENABLED=true
```

If the admin console intentionally uses a different hostname:

```bash
KC_HOSTNAME_ADMIN=https://sso-admin.example.com
```

## Validate the topology first

Identify which model is actually deployed:

- **Edge termination:** client -> HTTPS -> Nginx -> HTTP -> Keycloak
- **Re-encryption:** client -> HTTPS -> Nginx -> HTTPS -> Keycloak
- **TLS passthrough:** proxy does not terminate TLS

Do not mix configuration from these models.

## Validation workflow

### Backend reachability

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

## Context-path mismatches

If the public path is different from Keycloak's internal path, align it deliberately. A path mismatch can look like an authentication failure even when credentials and TLS are correct.

## Recovery sequence

1. Back up Nginx and Keycloak configuration.
2. Confirm edge/re-encrypt/passthrough topology.
3. Correct Keycloak hostname and proxy-header settings for the installed version.
4. Correct Nginx forwarded headers.
5. Run `nginx -t` before reload.
6. Restart or reload only the component whose runtime configuration changed.
7. Validate with `curl -IL` before testing through the application.
8. Confirm login, logout, admin-console access, and application callback URLs.

## Lesson

The failure was not simply "SSL is broken." It was a disagreement between the externally visible URL and what Keycloak believed the original request looked like. Compare scheme, host, port, path, and forwarded headers across every hop before changing authentication logic.