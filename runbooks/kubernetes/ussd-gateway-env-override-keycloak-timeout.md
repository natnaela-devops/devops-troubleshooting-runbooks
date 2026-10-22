# Kubernetes USSD Gateway: Docker ENTRYPOINT Overrides ConfigMap Values

**Incident date:** 2026-10-22  
**Platform:** RKE2 / Kubernetes, Argo CD, GitLab CI, Kaniko, Harbor  
**Workload:** Java 25 / Spring Boot USSD Gateway  
**Outcome:** Service functionality restored and verified for customer-state lookup, PIN authentication, menu display, and account lookup. Image-build standardization assigned to the application development team.

> **Public-safe case study:** Internal hostnames, IP addresses, credentials, telephone numbers, transaction identifiers, and customer payloads are deliberately omitted or replaced with placeholders.

## Symptoms

- A USSD application successfully deployed through GitLab → Harbor → GitOps → Argo CD and its Pod reached **Ready**, but downstream HTTP calls timed out.
- Customer-state lookup initially attempted an obsolete endpoint and later attempted the correct Service IP on the wrong port.
- After a temporary, direct-address configuration workaround restored customer-state lookup, PIN authentication timed out when the Keycloak client tried a stale endpoint.
- Kubernetes ConfigMap displayed the intended Service DNS configuration, and `kubectl exec ... printenv KC_URL` showed that value; however, the Java process used a different Keycloak URL.

## Evidence and isolation

1. Checked the deployment, running image, and rollout:

   ```bash
   kubectl -n <namespace> get deployment <gateway-deployment> \
     -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
   kubectl -n <namespace> rollout status deployment/<gateway-deployment>
   ```

2. Inspected the ConfigMap and deployment-level environment injection:

   ```bash
   kubectl -n <namespace> get configmap <gateway-configmap> \
     -o jsonpath='{.data.KC_URL}{"\n"}{.data.UGW_UTILS_BASE_URL}{"\n"}'

   kubectl -n <namespace> get deployment <gateway-deployment> -o json |
     jq '.spec.template.spec.containers[0] | {image,command,args,envFrom,env}'
   ```

   The deployment used `envFrom` to load a ConfigMap and Secret, with no explicit Kubernetes container `command` or `args`. Thus, the image's default entrypoint controlled startup.

3. Compared the environment of a newly executed shell with the original Java process:

   ```bash
   kubectl -n <namespace> exec deployment/<gateway-deployment> -- sh -c '
     echo "Shell KC_URL:"
     printenv KC_URL
     echo "Java process KC_URL:"
     tr "\000" "\n" < /proc/1/environ | grep "^KC_URL="
     echo "Java process command:"
     tr "\000" " " < /proc/1/cmdline; echo
   '
   ```

   **Finding:** the shell saw the intended Keycloak Service DNS, while PID 1 (Java) inherited the stale URL. The discrepancy is expected when a startup shell modifies its own environment before launching Java; `kubectl exec` starts a separate process from the container's original configuration.

4. Checked whether the Secret also supplies an overlapping key **without printing secret values**:

   ```bash
   kubectl -n <namespace> get secret <gateway-secret> -o json |
     jq -r '.data | keys[]' |
     grep -E '^(KC_URL|UGW_UTILS_BASE_URL|PG_HOST|YB_HOST)$' || true
   ```

5. Inspected the application Dockerfile. The pertinent pattern was:

   ```dockerfile
   COPY env.sh /app/env.sh
   ENTRYPOINT ["sh", "-c", "source /app/env.sh && java -Xmx${JAVA_XMX} -jar /app/app.jar"]
   ```

   The image-bundled `env.sh` used unconditional `export` statements, including obsolete dependency addresses. **This is the confirmed cause of the Java-versus-Kubernetes environment mismatch.** Whether any earlier wrong-port customer-service request also involved redirect behavior was not separately proven.

## Root cause

The application's image **baked in an environment-specific `env.sh` and sourced it at startup**. Exports in that file overwrote Kubernetes-provided variables in the startup shell before Java inherited the environment. As a result, Argo CD could be Synced, the Pod could be Ready, and interactive `kubectl exec printenv` could appear correct even while application requests went to an obsolete destination.

This was an **image build/startup configuration issue**, not evidence of broken cluster DNS. Service DNS resolution was explicitly tested and worked.

## Recovery and verification

- Coordinated with the development team to supply working downstream configuration during UAT, then agreed the development team would standardize image construction.
- Observed a newer application build successfully start on its intended HTTP port.
- Confirmed the database connection pool initialized successfully.
- A live USSD session retrieved the customer's status and language, prompted for a PIN, **authenticated successfully**, returned the main menu, and retrieved/cached an account list.
- These tests establish restoration of the **tested paths**, not comprehensive proof that all transactional menu flows work.

## Preventive controls

### Development-owned container standards

- Do not copy local `env.sh` or `.env` files containing environment-specific addresses or credentials into runtime images.
- Do not source scripts that silently override Kubernetes-supplied environment values.
- Use ConfigMaps and Secrets (or a supported secret manager) for runtime configuration.
- Prefer a minimal runtime image, a non-root user, and a signal-safe entrypoint, after testing application requirements.
- Keep the container listen port and Helm Service target port consistent.
- Define `.dockerignore` entries for local configuration and credentials; check repository history and rotate any previously exposed credentials.

Illustrative direct-start pattern (verify Java heap and application dependencies first):

```dockerfile
ENV JAVA_XMX=384m
ENTRYPOINT ["sh", "-c", "exec java -Xmx${JAVA_XMX} -jar /app/app.jar"]
```

### DevOps-owned CI/CD and GitOps controls

- On Merge Requests: run compilation, tests, Dockerfile/config checks, and secret scanning.
- Make critical tests **blocking** (avoid `allow_failure: true` for release gates).
- On an approved target-branch merge: build once, publish an immutable image, update the UAT GitOps image reference, and let Argo CD reconcile.
- Gate promotion on image scanning and add smoke tests for application dependencies after rollout.
- Validate **PID 1 environment**, not just `kubectl exec printenv`, when the container image uses a shell entrypoint.
- Do not treat Argo CD **Synced/Healthy** or Pod **Ready** as confirmation of business-flow success.
- Treat hardcoded ClusterIP workarounds as temporary; Service DNS is generally preferred once application-level routing is corrected and verified.

## Security and observability lessons

- Never publish raw `env.sh`, Secrets, banking internal addresses, customer MSISDNs, PIN-related XML, or access tokens in troubleshooting repositories.
- Mask customer identifiers and sensitive USSD payloads in application logs and shared incident attachments.
- Running a container as non-root is recommended; a failed attempt to remove an image-owned file inside a running Pod is **not** a permanent remediation. Rebuild the image and redeploy through GitOps.

## Final status

**Resolved for the tested login and account-lookup flows.** Application developers accepted ownership of container-image standardization; DevOps continues to own delivery pipeline and runtime deployment validation. Further end-to-end tests are appropriate before declaring every USSD feature verified.
