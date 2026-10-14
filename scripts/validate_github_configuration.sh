#!/bin/sh
set -eu

# These are public identifiers, never tokens or a client secret.
if [ "${CONFIGURATION:-}" != "Release" ]; then
    exit 0
fi
client_id="${REPO_MANAGER_GITHUB_CLIENT_ID:-}"
app_slug="${REPO_MANAGER_GITHUB_APP_SLUG:-}"
fail() {
    echo 'error: Configure the dedicated Repo Manager GitHub App public client ID and slug before a Release build. See Docs/GITHUB_APP_SETUP.md.' >&2
    exit 1
}
case "$client_id" in
    Iv*) ;;
    *) fail ;;
esac
case "$client_id" in
    *[!A-Za-z0-9.]*|Iv1.0000000000000001) fail ;;
esac
lower_client_id=$(printf '%s' "$client_id" | /usr/bin/tr '[:upper:]' '[:lower:]')
case "$lower_client_id" in
    *fixture*|*placeholder*|*example*|*dummy*) fail ;;
esac
[ "${#client_id}" -ge 8 ] && [ "${#client_id}" -le 100 ] || fail
case "$app_slug" in
    ''|*[!a-z0-9-]*|-*|*-) fail ;;
esac
[ "${#app_slug}" -le 100 ] || fail
