# Contributing to Tixa

Thank you for helping improve Tixa. Contributions may include bug reports,
documentation, tests, fixes, and new media-processing features.

## Before opening an issue

- Search existing issues to avoid duplicates.
- Run `sudo tixa doctor` and include relevant results without API keys.
- Include the Ubuntu/Debian release, Tixa revision, and exact reproduction
  steps.
- Remove domains, IP addresses, API keys, emails, and private file paths when
  they are not needed to understand the problem.

Security vulnerabilities must be reported using [SECURITY.md](SECURITY.md),
not a public issue.

## Development workflow

1. Fork the repository and create a focused branch.
2. Make the smallest change that solves the problem.
3. Keep persistent state out of the repository.
4. Validate modified Bash scripts with `bash -n`.
5. Validate Python changes with `python3 -m py_compile templates/main.py`.
6. Test creation or updates on a disposable Ubuntu/Debian VPS when changing
   installation, Nginx, systemd, DNS, or Certbot behavior.
7. Update documentation for user-visible behavior.
8. Open a pull request describing the problem, solution, verification, and
   operational impact.

## Pull-request expectations

- Do not commit credentials, certificates, registry data, or uploaded media.
- Preserve existing services and `/var/lib/tixa` during upgrades.
- Fail before destructive changes whenever a preflight check is possible.
- Add rollback behavior for migrations and other multi-step operations.
- Avoid silently stopping or reconfiguring software managed by the VPS owner.
- Keep commands compatible with the supported Debian/Ubuntu Bash environment.

By contributing, you agree that your contribution will be licensed under the
project's [MIT License](LICENSE).

## Maintainer release process

Tixa uses Semantic Versioning. To publish a release:

1. Decide whether the change is major, minor, or patch.
2. Update the root `VERSION` file without a leading `v`.
3. Update user-facing documentation and verify the installer.
4. Commit the release changes.
5. Create an annotated Git tag with a leading `v`.
6. Push the commit and tag, then create a GitHub Release from that tag.

Example:

```bash
printf '0.2.0\n' > VERSION
git add VERSION README.md
git commit -m "release: v0.2.0"
git tag -a v0.2.0 -m "Tixa v0.2.0"
git push origin main
git push origin v0.2.0
```

The tag and `VERSION` value must match. Do not move or reuse a published tag.
