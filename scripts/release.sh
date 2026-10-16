#!/bin/bash
# Publish a stable GitHub release consumed by the in-app updater.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=SHA0Q1AN047/lidlight
RELEASE_VERSION=$(cat VERSION)
if [[ ! "$RELEASE_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "VERSION must contain a stable version such as 1.3.0." >&2; exit 1
fi
if [ "$(git branch --show-current)" != main ] || [ -n "$(git status --porcelain)" ]; then
    echo "Commit the reviewed changes on main before publishing." >&2; exit 1
fi
if [ "$(git remote get-url lidlight)" != "https://github.com/$REPO.git" ]; then
    echo "The lidlight remote must point to $REPO." >&2; exit 1
fi
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ ! -f "$1" ]; }; then
    echo "Usage: bash scripts/release.sh [release-notes-file]" >&2; exit 1
fi
gh auth status >/dev/null
RELEASE_TAG="v$RELEASE_VERSION"
if gh release view "$RELEASE_TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "$RELEASE_TAG already exists. Increase VERSION; published assets must not be replaced." >&2; exit 1
fi
if git rev-parse --verify "refs/tags/$RELEASE_TAG" >/dev/null 2>&1; then
    echo "$RELEASE_TAG already exists locally. Choose a new version." >&2; exit 1
fi
RELEASE_TEMP=$(mktemp -d /private/tmp/lidlight-release.XXXXXX)
trap 'rm -rf "$RELEASE_TEMP"' EXIT
swiftc Sources/menubar/AppUpdater.swift Tests/AppUpdaterTests.swift -o "$RELEASE_TEMP/updater-tests"
"$RELEASE_TEMP/updater-tests"
swiftc Sources/menubar/CodexQuota.swift Sources/menubar/QuotaHistory.swift Sources/menubar/QuotaWeather.swift Tests/QuotaWeatherTests.swift -o "$RELEASE_TEMP/weather-tests"
"$RELEASE_TEMP/weather-tests"
swiftc Sources/menubar/ProcessCPU.swift Sources/menubar/HardwareSensors.swift Sources/menubar/PerformanceMonitor.swift Tests/PerformanceTests.swift -o "$RELEASE_TEMP/performance-tests"
"$RELEASE_TEMP/performance-tests"
swiftc Sources/menubar/GlassDashboardPanel.swift Tests/GlassPanelTests.swift -o "$RELEASE_TEMP/glass-panel-tests"
"$RELEASE_TEMP/glass-panel-tests"
swiftc Sources/menubar/CPUUsage.swift Sources/menubar/CatThermal.swift Sources/menubar/MenuBarIcon.swift Sources/menubar/MenuCatAnimator.swift Tests/MenuCatTests.swift -o "$RELEASE_TEMP/cat-tests"
"$RELEASE_TEMP/cat-tests"
swiftc Sources/menubar/CodexQuota.swift Sources/menubar/QuotaHistory.swift Sources/menubar/CatThermal.swift Sources/menubar/InstallVerification.swift Sources/Shared/ServiceReceipt.swift Tests/ImprovementsTests.swift -o "$RELEASE_TEMP/improvements-tests"
"$RELEASE_TEMP/improvements-tests"
swiftc Sources/menubar/PowerSupply.swift Sources/menubar/ProcessCPU.swift Sources/menubar/CodexQuota.swift Sources/menubar/QuotaHistory.swift Tests/AssistantFeaturesTests.swift -o "$RELEASE_TEMP/assistant-tests"
"$RELEASE_TEMP/assistant-tests"
swiftc Sources/menubar/DayCountdown.swift Tests/DayCountdownTests.swift -o "$RELEASE_TEMP/countdown-tests"
"$RELEASE_TEMP/countdown-tests"
swiftc Sources/menubar/CodexQuota.swift Sources/menubar/QuotaHistory.swift Tests/CodexQuotaTests.swift -o "$RELEASE_TEMP/quota-tests"
"$RELEASE_TEMP/quota-tests"
swiftc Sources/menubar/Features.swift Sources/menubar/PowerSupply.swift Sources/menubar/DayCountdown.swift Sources/Shared/PowerPolicy.swift Tests/FeatureStateTests.swift -o "$RELEASE_TEMP/feature-tests"
"$RELEASE_TEMP/feature-tests"
swiftc Sources/menubar/CodexQuota.swift Sources/menubar/QuotaHistory.swift Sources/menubar/Features.swift Sources/menubar/PowerSupply.swift Sources/menubar/DayCountdown.swift Sources/Shared/PowerPolicy.swift Sources/menubar/ProcessCPU.swift Sources/menubar/PerformanceMonitor.swift Sources/menubar/HardwareSensors.swift Tests/AuditRegressionTests.swift -o "$RELEASE_TEMP/audit-tests"
"$RELEASE_TEMP/audit-tests"
bash scripts/build.sh
python3 Tests/DaemonFeatureTests.py
python3 Tests/UninstallTests.py
# Publish the exact build. GitHub calculates the SHA-256 digest used by the updater.
git push lidlight main
git tag "$RELEASE_TAG"
git push lidlight "$RELEASE_TAG"
NOTES=(--generate-notes)
if [ "$#" -eq 1 ]; then NOTES=(--notes-file "$1"); fi
gh release create "$RELEASE_TAG" build/Lidlight.pkg --repo "$REPO" --verify-tag \
    --title "Lidlight $RELEASE_VERSION" --latest "${NOTES[@]}"
gh api "repos/$REPO/releases/tags/$RELEASE_TAG" --jq '.assets[] | select(.name == "Lidlight.pkg") | {name, size, digest}'
