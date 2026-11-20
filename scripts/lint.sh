#!/usr/bin/env bash
#
# Static checks that need no Azure credentials. Runs what ci.yml runs.
#   scripts/lint.sh          all checks
#   scripts/lint.sh fmt      terragrunt hcl fmt --check
#   scripts/lint.sh trivy    trivy config scan
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "${REPO_ROOT}"
export PATH="${HOME}/.local/bin:${PATH}"

run_fmt() {
  echo "== terragrunt hcl fmt --check"
  terragrunt hcl fmt --check --diff
}

run_trivy() {
  echo "== trivy config"
  trivy config --exit-code 1 --severity HIGH,CRITICAL --ignorefile .trivyignore --quiet \
    --skip-dirs '**/.terragrunt-cache' --skip-dirs '**/.terraform' .
}

case "${1:-all}" in
  fmt) run_fmt ;;
  trivy) run_trivy ;;
  all) run_fmt; run_trivy ;;
  *) echo "usage: $0 [fmt|trivy|all]" >&2; exit 2 ;;
esac
