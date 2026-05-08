# Renovate PR Review Checklist

## 1. Release Age Gate Verification
- Confirm the new version/release is at least 14 days old
- If the release is newer than 14 days, flag it and recommend waiting

## 2. Breaking Changes Analysis
- Compare current image/tag version with the new one
- For Docker images: check Docker Hub changelogs, GitHub release notes, or official docs for breaking API changes between versions
- Cross-reference Kubernetes deployment files in `kubernetes/apps/<app>/base/deployment.yaml` — check if environment variables, ports, commands, or health checks need updating
- Flag any container image that mentions "breaking" or major version bumps (e.g., MariaDB 11.x → 12.x)

## 3. Security Risk Assessment
- Search for CVEs/vulnerabilities using `gh search` on GitHub advisories and Docker Hub security notices
- Check if the new version fixes known vulnerabilities in the old version
- Flag images from unverified publishers or registries with weak access controls
- Only flag HIGH or CRITICAL severity CVEs, not medium/low ones

## 4. Version Compatibility
- Verify the new version is compatible with other services in the same app stack (e.g., if Paperless-ngx image updates, also check its Redis DB deployment)
- Check if database versions are synchronized (e.g., MariaDB upgrade should not be paired with an application that hasn't been tested against it)
- Flag mismatched or out-of-order upgrades (app updated before its dependencies)

## 5. Deployment Impact Analysis
- **Database migrations:** If a DB image is updating (e.g., `lscr.io/linuxserver/mariadb:11.4.8 → 11.5.x`), note that CloudNative-PG managed clusters handle minor version upgrades automatically, but major version jumps require migration plans. Check the app's deployment for any DB connection config changes needed.
- **Persistent volumes:** Flag if new container versions change default mount paths or data directory layouts
- **Configuration format changes:** If the app uses ConfigMaps (per AGENTS.md conventions), note if config file formats changed between versions

## 6. NixOS-Specific Checks (when PR modifies `flake.lock` or NixOS host configs)
- This repo's NixOS setup uses `nixos/nixpkgs/nixpkgs-unstable` — channel updates are inherently rolling
- Compare the old vs new git hash in flake.lock
- Assess if any service versions being upgraded have known breaking changes (check nixpkgs commit messages and release notes)
- Flag upgrades that touch `system.stateVersion` or require `nixos-rebuild` migration steps
- For multi-host setups (haproxy-1/2/3, opencode-1): note which hosts are affected and whether service restart patterns need coordination

## Output Format

Provide a concise summary with:

- **Status:** PASS / NEEDS_REVISION
- **Findings:** Bullet points for each category checked
- **Recommendation:** Clear go/no-go suggestion
