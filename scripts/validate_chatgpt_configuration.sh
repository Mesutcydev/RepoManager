#!/bin/sh
set -eu

case "${REPO_MANAGER_PRO_API_PROVIDERS_ENABLED:-NO}:${REPO_MANAGER_CHATGPT_MONETIZATION_CLEARED:-NO}" in
  YES:YES|YES:NO|NO:YES|NO:NO) ;;
  *) echo 'error: Pro and ChatGPT monetization flags must be YES or NO.' >&2; exit 1 ;;
esac
if [ "${REPO_MANAGER_PRO_API_PROVIDERS_ENABLED:-NO}" = YES ]; then
  case "${REPO_MANAGER_PRO_PRODUCT_ID:-}" in
    ''|*[!A-Za-z0-9._-]*) echo 'error: Set a valid StoreKit Pro product identifier before enabling purchases.' >&2; exit 1 ;;
  esac
fi
case "${CONFIGURATION:-Debug}" in
  Debug) ;;
  *)
    if [ "${REPO_MANAGER_PRO_API_PROVIDERS_ENABLED:-NO}" = YES ] &&
       [ "${REPO_MANAGER_CHATGPT_PLAN_USAGE_ENABLED:-NO}" = YES ] &&
       [ "${REPO_MANAGER_CHATGPT_MONETIZATION_CLEARED:-NO}" != YES ]; then
      # Optional Pro never controls ChatGPT access. Keep the external policy
      # question visible without treating an unclassified model as a denied grant.
      echo 'warning: OpenAI commercial classification for optional Pro is unconfirmed; ChatGPT must remain free. Review Docs/MONETIZATION.md before public submission.' >&2
    fi ;;
esac

# The user-authorized TestFlight beta tests the local integration on device.
# Public distribution requires the declared open-source publication.
case "${REPO_MANAGER_CHATGPT_PLAN_USAGE_ENABLED:-NO}" in
  YES|NO) ;;
  *) echo 'error: REPO_MANAGER_CHATGPT_PLAN_USAGE_ENABLED must be YES or NO.' >&2; exit 1 ;;
esac
if [ "${REPO_MANAGER_CHATGPT_PLAN_USAGE_ENABLED:-NO}" != 'YES' ]; then
  exit 0
fi
case "${CONFIGURATION:-Debug}" in
  Debug) exit 0 ;;
  TestFlight)
    if [ ! -f "${SRCROOT}/LICENSE" ]; then
      echo 'error: Include the app license in the TestFlight beta.' >&2
      exit 1
    fi
    exit 0 ;;
esac
case "${REPO_MANAGER_OPEN_SOURCE_URL:-}" in
  https://github.com/*/*|https://gitlab.com/*/*|https://codeberg.org/*/*) ;;
  *) echo 'error: Set REPO_MANAGER_OPEN_SOURCE_URL to the public source repository before distributing ChatGPT plan usage.' >&2; exit 1 ;;
esac
if [ ! -f "${SRCROOT}/LICENSE" ]; then
  echo 'error: Include the app license before distributing the open-source integration.' >&2
  exit 1
fi
# The URL is a declaration, not evidence of publication. Follow
# Docs/OPEN_SOURCE_RELEASE.md and verify anonymous source access before release.
