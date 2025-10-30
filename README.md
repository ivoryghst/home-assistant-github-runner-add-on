# GitHub Actions Runner Add-on for Home Assistant

[![GitHub Release][releases-shield]][releases]
![Project Stage][project-stage-shield]

Run a self-hosted GitHub Actions runner directly within your Home Assistant installation.

## Installation

1. Add this repository to your Home Assistant add-on store
2. Install the "GitHub Actions Runner" add-on
3. Configure the add-on (see below)
4. Start the add-on

## Configuration

### Required Options

**`repo_url`** - The URL of your GitHub repository or organization
- Repository: `https://github.com/username/repo`
- Organization: `https://github.com/organization`

**Authentication** (one of the following is required):

**`runner_token`** - Registration token from GitHub (traditional method)
- Get it from: Repository/Organization → Settings → Actions → Runners → New self-hosted runner
- Valid for 1 hour after generation
- Only needed for initial setup (configuration persists across restarts)
- **Limitation**: Must be regenerated every hour if runner needs to re-register

**`github_pat`** - Personal Access Token (recommended for persistent setups)
- Get it from: GitHub → Settings → Developer Settings → Personal Access Tokens
- **For Fine-grained tokens (recommended)**:
  - Select specific repository or organization
  - Grant "Actions" permission with "Read and write" access
  - Note: Fine-grained tokens for organizations are currently in beta
- **For Classic tokens**:
  - Required scopes for repository runners: `repo` (Full control of private repositories)
  - Required scopes for organization runners: `admin:org` (Full control of orgs and teams)
- **Advantage**: Never expires (unless you set an expiration), automatically fetches fresh registration tokens
- **Use case**: Ideal for long-running setups where automatic re-registration is needed

### Optional Options

**`runner_name`** - Custom name for your runner (default: auto-generated)

**`runner_labels`** - Comma-separated custom labels (default: `self-hosted,Linux,X64`)
- Example: `"production,fast"`
- Note: Custom labels replace defaults; include defaults explicitly if needed

**`debug_logging`** - Enable verbose logging (default: `false`)

### Example Configuration

**Using Registration Token (traditional method):**
```yaml
repo_url: "https://github.com/username/repo"
runner_token: "YOUR_RUNNER_TOKEN_HERE"
runner_name: "my-home-assistant-runner"
runner_labels: "self-hosted,Linux,X64,production"
debug_logging: false
```

**Using Personal Access Token (recommended):**
```yaml
repo_url: "https://github.com/username/repo"
github_pat: "YOUR_PERSONAL_ACCESS_TOKEN_HERE"
runner_name: "my-home-assistant-runner"
runner_labels: "self-hosted,Linux,X64,production"
debug_logging: false
```

## Features

- ✅ Persistent configuration across restarts (no token re-entry needed)
- ✅ Auto-recovery if runner is deleted from GitHub
- ✅ Graceful shutdown handling
- ✅ Multi-architecture support (amd64, aarch64, armhf, armv7, i386)
- ✅ Configurable runner labels
- ✅ Access to /share/addon_configs for workflow configuration storage

## Security Considerations

This addon runs without AppArmor restrictions to allow GitHub Actions workflows to access the system-wide `/addon_configs` directory. This is necessary because Home Assistant creates a symlink from `/share/addon_configs` to `/addon_configs`, and workflows need to write persistent configuration data through this path.

**Important**: GitHub Actions runners inherently execute arbitrary code from your workflows. Only use this addon with repositories you trust, and ensure your workflows come from trusted sources. The reduced container isolation aligns with the expected security model of self-hosted runners.

## Troubleshooting

**404 Error During Registration**
- Most common: Token expired (registration tokens valid for 1 hour) → **Solution**: Use a Personal Access Token (PAT) instead for automatic token renewal, or generate a new registration token
- Check URL format: `https://github.com/owner/repo` (no trailing slash)
- Verify you have admin permissions on the repository/organization
- If using PAT: Ensure it has the correct scopes:
  - Fine-grained tokens: "Actions" with "Read and write" access
  - Classic tokens: `repo` scope for repository runners, `admin:org` for organization runners
- Don't use workflow `${{ github.token }}`; use registration tokens or PATs

**Permission Denied When Writing to /addon_configs**
- The add-on automatically sets permissions on `/addon_configs` at startup
- Check the add-on logs to verify `/addon_configs` mount point was found
- Ensure `addon_configs:rw` is present in the `map:` section of your Home Assistant add-on configuration (this is already configured in the default config.yaml)
- If the mount point is not found, try restarting the add-on or reinstalling it
- The directory should be accessible at `/addon_configs` from within your workflows

## Support

Got questions or issues? Please open an issue on the [GitHub repository][github].

## Contributing

This is an active open-source project. We welcome contributions!

**Important**: All pull requests to the main branch must include a version bump in `config.yaml`. This is enforced by automated checks. See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

### Quick Contribution Guidelines

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. **Bump the version in `config.yaml`** (must be greater than current main version)
5. Update `CHANGELOG.md` with your changes
6. Submit a pull request

For detailed contribution guidelines, versioning rules, and development workflow, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License

Copyright (c) 2024

[releases-shield]: https://img.shields.io/github/release/skille/home-assistant-github-runner-add-on.svg
[releases]: https://github.com/skille/home-assistant-github-runner-add-on/releases
[project-stage-shield]: https://img.shields.io/badge/project%20stage-production%20ready-brightgreen.svg
[github]: https://github.com/skille/home-assistant-github-runner-add-on
