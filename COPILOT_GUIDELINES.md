# Copilot AI Guidelines for HA GitHub Runner Add-ons

Guidelines for contributors using AI tools to work on this project.

## Repository Structure

This is a multi-addon repository:
- Each addon has its own directory (e.g., `ha-github-runner/`)
- Each addon has its own `config.yaml`, `build.yaml`, `Dockerfile`, `run.sh`, etc.
- The root `repository.yaml` describes the repository

---

## Documentation Style

**Follow the simplified documentation pattern established in this repository:**

- Keep descriptions concise and focused
- Use bullet points for lists
- Avoid verbose AI-generated explanations
- No redundant information across files
- Focus on essential information only

**Example (Good):**
```markdown
## [1.4.0] - 2025-10-23
- Added configurable runner labels via `runner_labels` option
- Custom labels replace default labels when specified
```

**Example (Bad):**
```markdown
## [1.4.0] - 2025-10-23

### Added
- Configurable runner labels via `runner_labels` configuration option
- Support for comma-separated multiple labels
- Ability to customize runner labels for better workflow targeting
- Labels are automatically updated when configuration changes and add-on restarts

### Changed
- Default labels (self-hosted, Linux, architecture) are now replaceable with custom labels
- When custom labels are specified, they replace the default labels entirely
```

---

## Key Configuration Files

Per addon (in addon directory, e.g., `ha-github-runner/`):
- **config.yaml**: Add-on metadata, schema, options
- **build.yaml**: Docker images for each architecture
- **Dockerfile**: Container build instructions
- **run.sh**: Main execution script (uses bashio for logging)
- **README.md**: Add-on specific documentation

Repository level:
- **repository.yaml**: Repository metadata
- **README.md**: Repository overview
- **CHANGELOG.md**: Version history (simple bullet points)
- **CONTRIBUTING.md**: Contribution guidelines

---

## Technical Details

### Architecture Support
- amd64, aarch64, armv7, armhf, i386

### Key Dependencies
- Base images: `ghcr.io/home-assistant/*-base-debian:bookworm`
- Runtime: bash, curl, git, jq, tar, sudo, ca-certificates
- .NET Core: Installed via runner's `./bin/installdependencies.sh`

### Security
- Runner executes as non-root user (UID 1000)
- Configuration read from `/data/options.json` (not Supervisor API)
- Never commit tokens to version control

### Docker Best Practices
- Use official Home Assistant base images
- Combine RUN commands to reduce layers
- Run `./bin/installdependencies.sh` for .NET dependencies
- Clean up temporary files in same layer

---

## Runner Configuration

### Getting Tokens
- Repository: Settings → Actions → Runners → New self-hosted runner
- Organization: Settings → Actions → Runners → New runner
- Token expires in 1 hour
- Only needed for initial setup (config persists across restarts)

### Runner Labels
- Default: `self-hosted`, `Linux`, `X64` (or architecture-specific)
- Configurable via `runner_labels` option
- Use in workflows: `runs-on: self-hosted`

---

## Versioning

### 🚨 CRITICAL: Version Bump Required

**Every PR to main must bump version in the addon's `config.yaml`**

For example: `ha-github-runner/config.yaml`

- Enforced by automated CI checks
- New version must be greater than main branch version
- Follow semantic versioning: MAJOR.MINOR.PATCH

### Version Guidelines

- **PATCH** (1.0.X): Bug fixes, documentation updates
- **MINOR** (1.X.0): New features, backward-compatible changes
- **MAJOR** (X.0.0): Breaking changes

### Process

1. Check current main version:
   ```bash
   git show origin/main:ha-github-runner/config.yaml | grep version
   ```

2. Update the addon's `config.yaml` with higher version (e.g., `ha-github-runner/config.yaml`)

3. Update `CHANGELOG.md` with simple bullet points:
   ```markdown
   ## [1.0.6] - 2025-10-23
   - Fixed token validation
   - Added error messages
   ```

---

## Code Style

### Bash Scripts
- Use `#!/usr/bin/env bashio` shebang
- Enable error checking: `set -e`
- Quote variables: `"${VARIABLE}"`
- Use bashio logging: `bashio::log.info`, `bashio::log.error`

### Documentation
- Keep concise and focused (follow README.md and CHANGELOG.md pattern)
- Use bullet points, not verbose paragraphs
- Avoid redundancy across files
- Simple markdown formatting

### Common Pitfalls
- Don't use Supervisor API (read `/data/options.json` directly)
- Don't run as root (use `runner` user)
- Don't hardcode secrets or tokens
- Don't forget version bump in `config.yaml`

---

## Development Checklist

When making changes:

- [ ] Version bumped in addon's `config.yaml` (must be > main branch version)
- [ ] `CHANGELOG.md` updated with simple bullet points
- [ ] Documentation follows concise pattern (no verbose AI text)
- [ ] Configuration read from `/data/options.json`
- [ ] Non-root user execution maintained
- [ ] No hardcoded secrets or tokens
- [ ] Multi-architecture support maintained

---

For additional support, see [README.md](README.md), [CHANGELOG.md](CHANGELOG.md), and [CONTRIBUTING.md](CONTRIBUTING.md).
