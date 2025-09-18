#!/usr/bin/env bash
#
# Codex oriented Godot installer.
#
# This script installs the requested Godot version along with export templates
# under /opt/godot and exposes convenience symlinks.  It mirrors the automation
# expectations documented in tools/CodexAutomation.md so outside engineers can
# reproduce the CI environment locally.  The package installation stage now
# probes apt-cache policy to account for Ubuntu 24.04's transition to the t64
# variants of several libraries.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

GODOT_VERSION="4.4.1"
GODOT_TAG="${GODOT_VERSION}-stable"
GODOT_BASE_URL="https://downloads.tuxfamily.org/godotengine/${GODOT_VERSION}"
INSTALL_ROOT="/opt/godot/${GODOT_TAG}"
TEMPLATES_DIR="/usr/local/share/godot/templates/${GODOT_TAG}"

APT_PACKAGES=(
  ca-certificates
  curl
  unzip
  xdg-utils
  libx11-6
  libxcursor1
  libxinerama1
  libxrandr2
  libxi6
  libglib2.0-0
  libglu1-mesa
  libasound2
  libpulse0
  libvulkan1
)

# Map legacy package names to their t64 replacements.  Ubuntu 24.04 promotes
# these ABI compatible variants but still publishes the legacy names for older
# releases, so we dynamically switch based on availability.
declare -A PKG_RENAMES=(
  [libasound2]="libasound2t64"
  [libglib2.0-0]="libglib2.0-0t64"
)

get_candidate() {
  local pkg="$1"
  local candidate
  candidate=$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}' || true)
  if [[ -z "$candidate" ]]; then
    candidate="(none)"
  fi
  printf '%s' "$candidate"
}

for idx in "${!APT_PACKAGES[@]}"; do
  pkg="${APT_PACKAGES[$idx]}"
  alt="${PKG_RENAMES[$pkg]:-}"
  if [[ -n "$alt" ]]; then
    if [[ "$(get_candidate "$pkg")" == "(none)" && "$(get_candidate "$alt")" != "(none)" ]]; then
      APT_PACKAGES[$idx]="$alt"
    fi
  fi
done

apt-get update
apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
apt-get clean
rm -rf /var/lib/apt/lists/*

install -d "${INSTALL_ROOT}" "${TEMPLATES_DIR}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -f "${INSTALL_ROOT}/Godot_v${GODOT_TAG}_linux.x86_64" ]]; then
  curl -fL --retry 3 --retry-delay 5 \
    "${GODOT_BASE_URL}/Godot_v${GODOT_TAG}_linux.x86_64.zip" \
    -o "${TMP_DIR}/godot_editor.zip"
  unzip -o "${TMP_DIR}/godot_editor.zip" -d "${INSTALL_ROOT}"
fi
if [[ -f "${INSTALL_ROOT}/Godot_v${GODOT_TAG}_linux.x86_64" ]]; then
  chmod +x "${INSTALL_ROOT}/Godot_v${GODOT_TAG}_linux.x86_64"
fi

if [[ ! -f "${INSTALL_ROOT}/Godot_v${GODOT_TAG}_linux.x86_64_headless" ]]; then
  curl -fL --retry 3 --retry-delay 5 \
    "${GODOT_BASE_URL}/Godot_v${GODOT_TAG}_linux.x86_64_headless.zip" \
    -o "${TMP_DIR}/godot_headless.zip"
  unzip -o "${TMP_DIR}/godot_headless.zip" -d "${INSTALL_ROOT}"
fi
if [[ -f "${INSTALL_ROOT}/Godot_v${GODOT_TAG}_linux.x86_64_headless" ]]; then
  chmod +x "${INSTALL_ROOT}/Godot_v${GODOT_TAG}_linux.x86_64_headless"
fi

if [[ ! -f "${TEMPLATES_DIR}/version.txt" ]]; then
  curl -fL --retry 3 --retry-delay 5 \
    "${GODOT_BASE_URL}/Godot_v${GODOT_TAG}_export_templates.tpz" \
    -o "${TMP_DIR}/godot_templates.tpz"
  mkdir -p "${TMP_DIR}/templates"
  unzip -o "${TMP_DIR}/godot_templates.tpz" -d "${TMP_DIR}/templates"
  TEMPLATE_SRC="${TMP_DIR}/templates"
  if [[ -d "${TEMPLATE_SRC}/templates" ]]; then
    TEMPLATE_SRC="${TEMPLATE_SRC}/templates"
  fi
  cp -a "${TEMPLATE_SRC}/." "${TEMPLATES_DIR}/"
  printf '%s\n' "${GODOT_TAG}" > "${TEMPLATES_DIR}/version.txt"
fi

ln -sfn "${INSTALL_ROOT}/Godot_v${GODOT_TAG}_linux.x86_64" /usr/local/bin/godot4
ln -sfn "${INSTALL_ROOT}/Godot_v${GODOT_TAG}_linux.x86_64_headless" /usr/local/bin/godot4-headless

cat >/etc/profile.d/godot4.sh <<'PROFILE'
export GODOT4_BIN=/usr/local/bin/godot4
export GODOT4_HEADLESS=/usr/local/bin/godot4-headless
export GODOT4_TEMPLATES=/usr/local/share/godot/templates/${GODOT_TAG}
PROFILE
