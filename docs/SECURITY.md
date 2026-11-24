# Security Controls (shift-left, defense in depth)

| Layer | Control | Enforced by |
|---|---|---|
| Source | Secret scanning on full history | gitleaks (CI) |
| Code | SAST | bandit (CI) |
| Dependencies | Known-CVE audit; pinned versions | pip-audit (CI), pinned `requirements.txt` |
| Container | Multi-stage slim image, non-root uid 10001, no shell tooling added, healthcheck | `Dockerfile`, hadolint |
| Image | HIGH/CRITICAL (fixable) vulnerabilities fail the build | Trivy (CI) |
| Supply chain | SBOM (SPDX) artifact; keyless cosign signature of pushed digest | anchore/sbom-action, cosign |
| IaC | Misconfiguration scan; `terraform validate`; kubeconform schema validation | Trivy config, Terraform, kubeconform |
| Cluster admission | Namespace enforces Pod Security `restricted` | `k8s/base/namespace.yaml` |
| Runtime | readOnlyRootFilesystem, drop ALL caps, no privilege escalation, seccomp RuntimeDefault, SA token not mounted | `rollout.yaml` |
| Network | default-deny ingress+egress; allow only ingress-nginx and Prometheus -> app, DNS egress | `networkpolicy.yaml` |
| Resources | ResourceQuota + LimitRange + per-container limits (DoS containment) | `resources.yaml` |
| Delivery | Least-privilege workflow tokens (`contents: read` by default); cluster is never touched by CI (pull-based GitOps) | `ci.yml`, Argo CD |

## Verifying the signature (optional)
```bash
cosign verify ghcr.io/<user>/taskflow@<digest> \
  --certificate-identity-regexp 'https://github.com/<user>/devops-capstone/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Residual risks
Images are signed but the cluster does not yet *verify* signatures at admission (Kyverno/Sigstore policy-controller would close this).
Pod-to-pod mTLS (service mesh) is out of scope.
