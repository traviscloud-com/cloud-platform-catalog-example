#!/usr/bin/env bash
#
# Install the pinned, checksum-verified CLI tools this repo's checks need
# (terragrunt, gitleaks, trivy) into ~/.local/bin. Idempotent;
# used locally and by .github/workflows/ci.yml. terraform itself comes from
# .tool-versions (asdf/mise) or the CI setup action.
#
# Usage: scripts/install-tools.sh [tool ...]     (default: all)
set -euo pipefail

GITLEAKS_VERSION="8.24.3"
TRIVY_VERSION="0.76.2"
TERRAGRUNT_VERSION="1.1.1"

INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
mkdir -p "${INSTALL_DIR}"

case "$(uname -s)_$(uname -m)" in
  Linux_x86_64) os=linux; arch=amd64; trivy_os=Linux; trivy_arch=64bit ;;
  Linux_aarch64) os=linux; arch=arm64; trivy_os=Linux; trivy_arch=ARM64 ;;
  Darwin_arm64) os=darwin; arch=arm64; trivy_os=macOS; trivy_arch=ARM64 ;;
  *) echo "Unsupported platform $(uname -s)/$(uname -m)" >&2; exit 1 ;;
esac

# sha256 from each project's official release checksum file.
declare -A SHA=(
  ["terragrunt_linux_amd64"]="98b0400ba1ae27120adeeb98ba97e75eba0bab0b4cbd7b8bb148d4ed29e2f823"
  ["terragrunt_linux_arm64"]="9662356c40130bfbcd20e88e556dfa33e487c31af153803aca85c8a299d48ab6"
  ["terragrunt_darwin_arm64"]="339ac06bf16e3b4a382394a6174497700296cc485a5172ce37eba725e720c83c"
  ["gitleaks_linux_amd64"]="9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c"
  ["gitleaks_linux_arm64"]="5f2edbe1f49f7b920f9e06e90759947d3c5dfc16f752fb93aaafc17e9d14cf07"
  ["gitleaks_darwin_arm64"]="b90f13bb8c90ab72083d9b0c842e39dafb82c0e5c3f872f407366b7a58909013"
  ["trivy_linux_amd64"]="bc0fc726e017b8927a62b2d3531d7a84ee01769daf5c99ed866dced54089fdbf"
  ["trivy_linux_arm64"]="ab9d51f86e6a5fb936f605faff6b593ac51bc378fff4d3e8b9d58358b9c367c3"
  ["trivy_darwin_arm64"]="ae7ea358326960406b703c77b2ac490190797d80b306b5b50c2a27221da0a5b8"
)

tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT

installed_version() { # tool -> version string or ""
  command -v "$1" >/dev/null 2>&1 || { echo ""; return; }
  case "$1" in
    gitleaks) gitleaks version 2>/dev/null ;;
    terragrunt) terragrunt --version 2>/dev/null | head -1 | sed -E 's/.*version v([0-9.]+).*/\1/' ;;
    trivy) trivy --version 2>/dev/null | head -1 | sed -E 's/.*Version: ([0-9.]+).*/\1/' ;;
  esac
}

fetch() { # url dest key
  curl -sSfL -o "$2" "$1"
  echo "${SHA[$3]}  $2" | sha256sum -c - >/dev/null || { echo "CHECKSUM MISMATCH for $3 - aborting." >&2; exit 1; }
}

install_gitleaks() {
  local f="gitleaks_${GITLEAKS_VERSION}_${os}_$( [ "$arch" = amd64 ] && echo x64 || echo arm64 ).tar.gz"
  fetch "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${f}" "${tmp}/${f}" "gitleaks_${os}_${arch}"
  tar -xzf "${tmp}/${f}" -C "${tmp}" gitleaks && install -m 0755 "${tmp}/gitleaks" "${INSTALL_DIR}/gitleaks"
}
install_terragrunt() { # raw binary, checksum from the release SHA256SUMS
  fetch "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_${os}_${arch}" "${tmp}/terragrunt" "terragrunt_${os}_${arch}"
  install -m 0755 "${tmp}/terragrunt" "${INSTALL_DIR}/terragrunt"
}
install_trivy() {
  local f="trivy_${TRIVY_VERSION}_${trivy_os}-${trivy_arch}.tar.gz"
  fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${f}" "${tmp}/${f}" "trivy_${os}_${arch}"
  tar -xzf "${tmp}/${f}" -C "${tmp}" trivy && install -m 0755 "${tmp}/trivy" "${INSTALL_DIR}/trivy"
}

tools=("$@"); [ ${#tools[@]} -eq 0 ] && tools=(terragrunt gitleaks trivy)
for tool in "${tools[@]}"; do
  want_var="$(echo "${tool}" | tr 'a-z-' 'A-Z_')_VERSION"; want="${!want_var}"
  if [[ "$(installed_version "${tool}")" == "${want}" ]]; then
    echo ">> ${tool} ${want} already installed"
  else
    echo ">> installing ${tool} ${want}"; "install_${tool}"
  fi
done
case ":${PATH}:" in *":${INSTALL_DIR}:"*) ;; *) echo "NOTE: add ${INSTALL_DIR} to your PATH." ;; esac
