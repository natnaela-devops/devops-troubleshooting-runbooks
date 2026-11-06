# Trust a Partner TLS Certificate in Java: Distro JDK vs Tarball JDK

A Java service makes outbound HTTPS calls to a partner endpoint whose certificate is issued by a private CA. The task was to add the partner's certificate to Java's trust and move the service off a custom truststore passed on the command line.

The same procedure behaved differently on two hosts, because one ran a distribution-packaged JDK and the other ran a JDK extracted from a tarball. This runbook covers both.

## Symptoms and starting state

- The service was launched with `-Djavax.net.ssl.trustStore=<path>/<truststore>.jks` and `-Djavax.net.ssl.trustStorePassword=...`, so the password was visible to anyone who could run `ps`.
- The partner certificate was delivered as a `.cer` file, and the filename differed per host.
- After `update-ca-certificates` on the second host, Java's `cacerts` did not get the expected `debian:<name>.pem` alias. The only entry was the `<alias>` from an earlier manual `keytool` import.

## 1. Identify which kind of JDK is in use

```bash
readlink -f "$(which java)"
dpkg -l ca-certificates-java | tail -1
ls -l "$(dirname "$(readlink -f "$(which java)")")/../lib/security/cacerts"
```

| Observation | JDK type | Use |
|---|---|---|
| Path under `/usr/lib/jvm/...`, `ca-certificates-java` is `ii`, `cacerts` is a symlink to `/etc/ssl/certs/java/cacerts` | Distribution package | Route A |
| Path such as `/opt/<jdk>/...`, `ca-certificates-java` is `un` or missing, `cacerts` is a plain file | Tarball install | Route B |

A plain `cacerts` file owned by an unfamiliar numeric UID is a strong hint that the JDK came from a tarball.

## 2. Inspect what the application trusts today

```bash
ps aux | grep '[j]ava'                         # look for -Djavax.net.ssl.trustStore
grep -n trustStore <launch-script>.sh
keytool -list -keystore <path>/<truststore>.jks -storepass '<password>'
```

Every entry in the custom truststore must also end up in `cacerts`. If you move only one certificate, the other connections break after the switch.

## 3. Normalise the certificate to PEM and verify it

A `.cer` file may be PEM or DER. Try PEM first, then fall back to DER:

```bash
CER="<partner-cert>.cer"
openssl x509 -in "$CER" -out /tmp/partner.crt 2>/dev/null \
  || openssl x509 -inform DER -in "$CER" -out /tmp/partner.crt
openssl x509 -in /tmp/partner.crt -noout -subject -issuer -enddate -fingerprint -sha256
```

Check the subject, issuer, and expiry. If more than one certificate file is lying around, compare fingerprints before choosing one:

```bash
for f in *.cer *.crt; do
  echo "== $f"
  openssl x509 -in "$f" -noout -subject -enddate -fingerprint -sha256 2>/dev/null \
    || openssl x509 -inform DER -in "$f" -noout -subject -enddate -fingerprint -sha256
done
```

The first failure on the second host was simply a wrong filename. `openssl` reported `No such file or directory`, and the follow-up command then failed because `/tmp/partner.crt` had never been created.

## 4a. Route A: distribution JDK, via the system CA store

```bash
cp /tmp/partner.crt /usr/local/share/ca-certificates/<partner-name>.crt
update-ca-certificates
keytool -list -cacerts -storepass changeit | grep -i <partner-name>   # expect debian:<partner-name>.pem
```

- The file in `/usr/local/share/ca-certificates/` must end in `.crt` and be PEM.
- `update-ca-certificates` rebuilds `/etc/ssl/certs/`, and through the `ca-certificates-java` hook it also rebuilds `/etc/ssl/certs/java/cacerts`, which the JDK's `cacerts` symlinks to.
- This survives package upgrades because the certificate lives in the source directory that `cacerts` is regenerated from. A bare `keytool -importcert` into this `cacerts` edits a generated file and can be lost on regeneration.
- `rehash: warning: skipping ca-certificates.crt, it does not contain exactly one certificate or CRL` is harmless. That file is the combined bundle.

## 4b. Route B: tarball JDK, by direct import

`update-ca-certificates` does not reach a tarball JDK. Import straight into its `cacerts`:

```bash
keytool -importcert -noprompt -alias <alias> -file /tmp/partner.crt -cacerts -storepass changeit
keytool -list -cacerts -storepass changeit -alias <alias> -v | grep SHA256
```

Compare the SHA-256 against the value from step 3. Keep a copy of the source certificate and a backup of the modified store:

```bash
cp /tmp/partner.crt <app-dir>/partner.crt
cp "$(dirname "$(readlink -f "$(which java)")")/../lib/security/cacerts" <app-dir>/cacerts.with-partner.bak
```

- apt never touches this JDK, so package updates cannot drop the import.
- Replacing the JDK directory with a newer tarball does drop it, because the new JDK ships its own `cacerts`. Re-run the import after any JDK swap.
- Do not install `ca-certificates-java` to "fix" this. It maintains `/etc/ssl/certs/java/cacerts`, which this JDK doesn't read, and on some releases it pulls in a distribution OpenJDK as a dependency.

## 5. Test the handshake from a fresh JVM

The running service won't see the change until it restarts. Test with a throwaway JVM first:

```bash
cat > /tmp/TlsCheck.java <<'EOF'
public class TlsCheck {
  public static void main(String[] a) throws Exception {
    String host = a[0]; int port = a.length > 1 ? Integer.parseInt(a[1]) : 443;
    try (var s = (javax.net.ssl.SSLSocket) javax.net.ssl.SSLSocketFactory.getDefault().createSocket(host, port)) {
      s.startHandshake();
      System.out.println("OK  " + s.getSession().getProtocol() + "  " + s.getSession().getPeerPrincipal());
    }
  }
}
EOF
java /tmp/TlsCheck.java <partner-host> <port>
```

`OK TLSv1.x CN=<partner-host>` means trust works. `PKIX path building failed` means the chain is still not trusted.

## 6. Switch the service to `cacerts`

1. Remove both `-Djavax.net.ssl.trustStore=...` and `-Djavax.net.ssl.trustStorePassword=...` from the launch script. A custom `trustStore` replaces `cacerts` entirely rather than adding to it.
2. Restart the service. The JVM reads its truststore only at startup.
3. Watch the application logs for `PKIX path building failed` on the first outbound call.

Rollback: restore the two flags and restart. Keep the old truststore file until the switch is confirmed.

## Renewal: trust the issuer, not the leaf

Importing the partner's server (leaf) certificate works until the partner renews it. The new certificate has a different fingerprint, and TLS fails on the renewal date. Prefer trusting the issuing CA and its root:

```bash
openssl s_client -connect <partner-host>:<port> -showcerts </dev/null
```

Save the issuer certificate(s), or request the CA chain from the partner, then add them through Route A or B under their own aliases. Record the leaf certificate's expiry in a calendar regardless.

## Pitfalls

- `$JAVA_HOME` is often unset, and `sudo` strips it, so `$JAVA_HOME/lib/security/cacerts` collapses to `/lib/security/cacerts`. Use `keytool -cacerts`, which always targets the running JDK's default store.
- Running `sudo` as root is unnecessary and is what drops the environment.
- `ps aux | grep <name>` matches the grep process itself. Use `pgrep -af <name>` or `grep '[n]ame'`.
- A stale `.pid` file next to a JAR that isn't running says nothing about the process that is. Check the launch script and logs before assuming which JAR should be live.
