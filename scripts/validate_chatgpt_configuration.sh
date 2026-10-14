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
  Debug|TestFlight) ;;
  *)
    if [ "${REPO_MANAGER_PRO_API_PROVIDERS_ENABLED:-NO}" = YES ] &&
       [ "${REPO_MANAGER_CHATGPT_PLAN_USAGE_ENABLED:-NO}" = YES ] &&
       [ "${REPO_MANAGER_CHATGPT_MONETIZATION_CLEARED:-NO}" != YES ]; then
      echo 'error: Confirm OpenAI access for this monetized distribution model before offering paid Pro with ChatGPT.' >&2
      exit 1
    fi ;;
esac

# The user-authorized TestFlight beta tests the local integration on device.
# The public Release still requires the chosen free open-source publication.
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
