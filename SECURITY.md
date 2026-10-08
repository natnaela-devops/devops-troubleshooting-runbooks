# Security

Do not commit:

- production or UAT passwords
- internal/private IP addresses tied to a real environment
- private keys (`.key`)
- client or broker keystores (`.p12`, `.jks`)
- truststores that contain environment-specific certificate material
- real broker/client certificates or CA material from private infrastructure
- Kubernetes Secret values
- tokens, API keys, or connection strings

All examples in this repository should use placeholders, synthetic addresses, and non-sensitive sample identities.

When documenting TLS or mTLS work, publish the procedure and configuration pattern only. Keep real CA keys, broker/client certificates, keystore passwords, checksums of private delivery artifacts, and environment-specific endpoints outside the repository.
