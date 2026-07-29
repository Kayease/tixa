# Security Policy

## Supported versions

Security fixes are applied to the latest revision of the `main` branch. Users
should keep both the installed CLI and generated services current:

```bash
sudo tixa self-update
sudo tixa update --all
```

## Reporting a vulnerability

Please do not disclose security vulnerabilities in a public issue.

Use GitHub's private vulnerability reporting feature for this repository. If
private reporting is unavailable, contact the repository owner through a
private channel listed on the owner's GitHub profile.

Include:

- The affected version or commit
- A clear description of the vulnerability
- Reproduction steps or a minimal proof of concept
- Potential impact
- Any suggested mitigation

Do not include real API keys, certificates, personal data, or production media.

## Operational security

- Protect `/var/lib/tixa/registry.json`; it contains API keys.
- Rotate exposed keys with `sudo tixa apikey rotate SERVICE`.
- Restrict SSH access and keep the operating system patched.
- Back up original media and persistent state.
- Review the generated root-running systemd services before using Tixa in a
  high-security or multi-tenant environment.

