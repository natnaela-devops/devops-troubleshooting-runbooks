# FortiVPN Certificate and DNS Troubleshooting

This runbook covers SSL VPN failures where the gateway is reachable but the client rejects the server certificate, DNS changes after connection, or NetworkManager credentials are not persisted correctly.

## Inspect the gateway certificate

```bash
openssl s_client -connect <vpn-gateway>:<port> -servername <vpn-gateway> </dev/null 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Check whether the hostname or IP used by the client exists in the certificate SAN.

## Test the HTTPS endpoint

```bash
curl -kIsS --max-time 15 https://<vpn-gateway>:<port>/ | head
```

This confirms basic TCP/TLS reachability independently of the VPN client.

## NetworkManager/OpenFortiVPN checks

```bash
nmcli connection show
nmcli connection show '<VPN connection name>'
nmcli connection up '<VPN connection name>'
```

If the connection needs a password stored in NetworkManager, prefer using NetworkManager's secret handling rather than placing credentials directly in reusable shell history.

## Verify routes and DNS after connection

```bash
ip route
resolvectl status 2>/dev/null || cat /etc/resolv.conf
nmcli device show | grep -E 'IP4.DNS|IP4.ROUTE'
```

## Common causes

### Certificate name mismatch

The gateway certificate SAN does not match the hostname/IP used by the client. The correct fix is a certificate with the right SAN or connecting through the intended DNS name. Avoid permanently disabling certificate verification.

### VPN connects but internal names do not resolve

Inspect DNS servers and split-DNS settings delivered by the VPN. Confirm the expected internal DNS server is reachable over the tunnel.

### Saved connection prompts repeatedly for a password

Inspect the NetworkManager connection secret flags and verify the password is actually stored through the supported secret mechanism.

## Validation

After the tunnel is established:

```bash
ip addr
ip route
ping -c 2 <internal-test-host>
getent hosts <internal-name>
```

Validate both routing and name resolution; a successful tunnel alone does not prove application connectivity.
