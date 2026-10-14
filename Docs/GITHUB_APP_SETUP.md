# Dedicated Repo Manager GitHub registration

Registered 2026-10-12 under **Mesutcydev** after the user approved the registration and its exact permissions. The verified public client ID and app slug are configured in `project.yml`.

## Why this is required

TestFlight exposed a developer form and asked each person to register an App. Repo Manager must own a dedicated registration and bundle its public identity. Users should only sign in and select repository access. The reference/SiteAgent registration must not be reused.

The screen uses bundled public identity, external Safari, recoverable device-flow states and an optional secure token field. The app owns the pending device-code attempt independently of the account sheet. Backgrounding locks the workspace and pauses polling; returning restores the workspace and resumes the unexpired attempt. Explicit cancellation, expiration or app termination ends pairing. Device codes stay in memory; browser handoff does not grant repository access by itself.

## Registered App

**[Repo Manager by Mesutcydev](https://github.com/apps/repo-manager-by-mesutcydev)** was created manually in the owner's GitHub App settings. App ID: `5283355`. Homepage: `https://github.com/Mesutcydev`, the existing public profile. No new project or website was published.

- **Device Flow** and **Expire user authorization tokens** are enabled and verified in the saved settings.
- **Request user authorization (OAuth) during installation** is off.
- Callback/setup URLs are empty; no callback server is required for device flow.
- **Webhook Active** is off, with no URL or event subscriptions.
- Installation is available to **Any account** so testers can select their repositories.
- No App private key or client secret was generated, downloaded, copied or stored during this registration.

Verified repository permissions reflect the requested complete catalog:

| Permission | Access | App features |
| --- | --- | --- |
| Metadata | Read | Repository identity |
| Contents | Read/write | Files, history, branches, tags, releases |
| Workflows | Read/write | Reviewed workflow edits |
| Issues | Read/write | Issues, comments, labels, milestones |
| Pull requests | Read/write | Reviews, merge, reviewers |
| Discussions | Read/write | Repository collaboration |
| Actions | Read/write | Runs, artifacts, dispatch |
| Checks | Read | Check status |
| Deployments | Read/write | Deployment reviews |
| Administration | Read/write | Reviewed settings, permissions, transfer, deletion |
| Environments | Read/write | Configuration and secrets |
| Webhooks | Read/write | Reviewed webhook administration |
| Secrets | Read/write | Native Actions secret administration |
| Dependabot secrets | Read/write | Native secret administration |
| Dependabot alerts | Read/write | Reviewed alert updates |
| Code scanning alerts | Read/write | Reviewed alert updates |
| Secret scanning alerts | Read/write | Reviewed alert updates |

Organization **Projects: read/write** is configured for optional linked Projects v2 tools where an organization grants it. No billing, organization administration, members, email, SSH-key or profile-write permission is configured. Account owners choose repository access during installation. Native account roles, repository grants and immutable reviews continue to constrain tools.

GitHub's initial registration-success notice requested an App private key, but the actual installation succeeded with zero key pairs and zero client secrets configured. No key or secret was generated or downloaded. A private key was not required for this installation; GitHub documents private keys for authenticating as the App itself and issuing installation tokens. Repo Manager uses device-flow user tokens. An App private key or client secret must never be embedded in Repo Manager or committed to this project. See [GitHub's private-key documentation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps).

Verify labels and token support against [GitHub's permission table](https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps), follow its [registration guide](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app), and use [device-flow refresh without a client secret](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens).

## Public build configuration

The registration's public API metadata matches these values in `project.yml`. The Xcode project has been regenerated with XcodeGen:

```
REPO_MANAGER_GITHUB_CLIENT_ID: Iv23liukghEjpO3HgPsd
REPO_MANAGER_GITHUB_APP_SLUG: repo-manager-by-mesutcydev
```

These expand into Info.plist keys `RepoManagerGitHubClientID` and `RepoManagerGitHubAppSlug`. They are public metadata, not credentials. Legacy encrypted user `githubClientID` preferences are ignored for new sign-in. Existing account client IDs remain for their own refresh/reconnection.

Release builds fail if identity is missing, malformed, an OAuth App ID or an obvious placeholder. Debug shows a clear unavailable state. `--github-pairing-fixtures` requires both `DEBUG` and `--ui-fixtures`; its synthetic identity/transport make no network requests and cannot enable Release sign-in.

Access/refresh tokens remain in one atomic nonsynchronizing device-only Keychain item per account. Device codes stay in memory. Neither is copied to clipboard, logs, files or build configuration.

## Registration verification

GitHub's public App API confirms the owner, App ID, client ID, slug, permissions and empty event subscriptions. A live unauthenticated device-code request succeeded with the trusted verification URL `https://github.com/login/device`; both codes were discarded in memory without printing, saving, authorizing or polling. This confirms device flow is enabled, but does not establish successful user sign-in, refresh or repository access.

## Test your own installation

Install your dedicated GitHub App on a disposable repository using **Only select repositories**. Configure your own public client ID and slug when distributing a fork. Keep repository grants narrow; reviewed writes still require the user's native approval.

1. Run device-flow expiry, cancellation and background-continuation fixtures and native pairing UI checks.
2. Verify external Safari handoff, retained pending code, foreground restoration and explicit cancellation.
3. Test real sign-in and refresh against your disposable installation with the account owner's authorization.
4. Verify scoped reads and cancellation before any reviewed write.
5. Verify bundled identity, source/binary checks and distribution profiles before an uploaded build.

Fixture success does not prove a real registration is enabled or an account has granted repository access.
