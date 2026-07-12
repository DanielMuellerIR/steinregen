# Security Policy

## Supported versions

Security fixes target the latest public release and the current `main` branch. Older builds are not
maintained separately.

## Reporting a vulnerability

Please use GitHub's **Security → Report a vulnerability** form once the repository is public and
private vulnerability reporting is enabled. If that form is unavailable, open a minimal issue
asking the maintainer for a private contact channel. Do not include exploit details, credentials,
personal data, or other sensitive material in a public issue.

## Data and network scope

Steinregen is an offline game. It has no account system, server component, analytics, advertising,
telemetry, or application network code. Preferences and high scores stay in the local
`UserDefaults` container. Build and release tooling does use external services only when a
maintainer explicitly invokes Apple notarization or GitHub publication commands.
