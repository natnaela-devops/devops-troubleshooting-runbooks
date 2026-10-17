# Nginx 502/504 upstream failures and SELinux connection denials

This runbook separates four failure classes that are often grouped together under a generic "Nginx is down" report: unreachable upstreams, upstream timeouts, application failures, and SELinux policy denials.

## Typical symptoms

- `502 Bad Gateway`
- `504 Gateway Timeout`
- Nginx error log contains `connect() failed (13: Permission denied)`
- Backend service works with local `curl`, but Nginx cannot proxy to it
- Backend accepts connections but responses stall or time out

## 1. Read the error before tuning anything

```bash
sudo tail -n 100 /var/log/nginx/error.log
sudo journalctl -u nginx -n 100 --no-pager
```

Do not immediately increase buffers or timeouts. A 502 can be caused by connection refusal, process crashes, TLS mismatch, permission denial, DNS failure, or malformed upstream responses. A 504 usually points more directly to an upstream that did not respond in time.

## 2. Verify the upstream process and socket

```bash
ss -lntp
systemctl status <upstream-service> --no-pager
curl -v http://127.0.0.1:<port>/health
```

If the service is expected to listen on a non-loopback address, verify the exact bind address as well as the port.

Useful checks:

```bash
ps -ef | grep -i '<service-name>'
sudo lsof -i :<port>
```

If local `curl` fails, fix the application or service first. Nginx is not the root cause.

## 3. Test from the Nginx execution context

A backend can be reachable from an interactive shell while still being blocked for the Nginx worker process by SELinux or another policy layer.

On SELinux-enabled systems:

```bash
getenforce
sudo ausearch -m AVC -ts recent
sudo journalctl -t setroubleshoot --since '-15 min'
```

If the logs prove that Nginx/httpd is being denied outbound network access and the architecture requires reverse-proxy connections, inspect the relevant boolean:

```bash
getsebool httpd_can_network_connect
```

Enable it only when justified by the deployment model:

```bash
sudo setsebool -P httpd_can_network_connect 1
```

Do not disable SELinux globally to make the proxy work. Use audit evidence to correct the specific policy requirement.

## 4. Validate the Nginx upstream definition

```bash
sudo nginx -t
sudo nginx -T
```

Check for:

- wrong hostname or port;
- HTTP configured against an HTTPS upstream, or the reverse;
- stale DNS resolution assumptions;
- incorrect URI/path rewriting;
- an upstream bound only to `127.0.0.1` when Nginx is on another host;
- missing SNI/hostname handling for HTTPS upstreams.

## 5. Distinguish connection failure from timeout

### Connection refused

Usually means nothing is listening on the target socket, the service is bound to a different address, or a local/network policy rejects the connection.

```bash
nc -vz <upstream-host> <port>
curl -v http://<upstream-host>:<port>/
```

### Timeout

Check network path and application latency separately:

```bash
ping -c 3 <upstream-host>
tracepath <upstream-host>
curl -v --max-time 10 http://<upstream-host>:<port>/
```

A reachable TCP port does not prove the application can produce a valid response within the required time.

## 6. Only tune buffers when the logs prove a header/buffer problem

Large authentication cookies or response headers can require larger proxy buffers, but this should be evidence-driven.

If Nginx explicitly logs errors such as `upstream sent too big header`, a controlled example is:

```nginx
proxy_buffer_size 16k;
proxy_buffers 8 16k;
proxy_busy_buffers_size 32k;
```

The correct values depend on observed header size and workload. Avoid copying very large buffer values as a universal fix; they increase per-request memory use and can hide an application-side problem.

## 7. Only tune timeouts when upstream latency is expected

Example directives:

```nginx
proxy_connect_timeout 5s;
proxy_send_timeout 30s;
proxy_read_timeout 30s;
```

Before increasing `proxy_read_timeout`, determine why the upstream is slow. Check application logs, database latency, thread/connection pools, CPU, memory, and downstream dependencies.

## 8. Validate recovery

After changes:

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -v http://<upstream-host>:<port>/health
curl -vk https://<public-endpoint>/health
sudo tail -f /var/log/nginx/error.log
```

Validate both direct upstream behavior and the full proxied request path.

## Root-cause pattern

`502` and `504` are symptoms at the proxy boundary, not root causes. The fastest triage path is:

1. read the exact Nginx error;
2. verify the upstream process and socket;
3. test direct application behavior;
4. check SELinux/firewall/network policy;
5. verify protocol, host, port, and path;
6. tune buffers/timeouts only when logs justify it.
