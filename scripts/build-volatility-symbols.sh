#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

out_dir="${1:-$PROJECT_ROOT/generated/m1/evidence/volatility}"
kernel_version="$(uname -r)"
mkdir -p "$out_dir"
symbol_swap="/swapfile-gridshield-volatility"
created_symbol_swap=0

cleanup_symbol_swap() {
  if [[ "$created_symbol_swap" -eq 1 ]]; then
    sudo swapoff "$symbol_swap" >/dev/null 2>&1 || true
    sudo rm -f "$symbol_swap"
  fi
}
trap cleanup_symbol_swap EXIT

ensure_symbol_swap() {
  local mem_kb swap_lines
  mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
  swap_lines="$(swapon --show --noheadings 2>/dev/null | wc -l)"
  if [[ "$mem_kb" -lt 3500000 && "$swap_lines" -eq 0 && ! -e "$symbol_swap" ]]; then
    sudo fallocate -l 4G "$symbol_swap"
    sudo chmod 600 "$symbol_swap"
    sudo mkswap "$symbol_swap" >/dev/null
    sudo swapon "$symbol_swap"
    created_symbol_swap=1
  fi
}

install_dwarf2json() {
  if command -v dwarf2json >/dev/null 2>&1; then
    return 0
  fi
  sudo apt-get update
  sudo apt-get install -y git golang-go xz-utils
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git clone --depth 1 https://github.com/volatilityfoundation/dwarf2json.git "$tmp/dwarf2json"
  (cd "$tmp/dwarf2json" && go build)
  sudo install -m 0755 "$tmp/dwarf2json/dwarf2json" /usr/local/bin/dwarf2json
}

find_vmlinux() {
  for p in \
    "/usr/lib/debug/boot/vmlinux-$kernel_version" \
    "/boot/vmlinux-$kernel_version"; do
    if [[ -r "$p" ]]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

maybe_install_dbgsym() {
  if find_vmlinux >/dev/null 2>&1; then
    return 0
  fi
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi
  codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  if [[ -z "$codename" ]]; then
    return 1
  fi
  sudo apt-get update
  sudo apt-get install -y ubuntu-dbgsym-keyring || true
  {
    echo "deb http://ddebs.ubuntu.com ${codename} main restricted universe multiverse"
    echo "deb http://ddebs.ubuntu.com ${codename}-updates main restricted universe multiverse"
  } | sudo tee /etc/apt/sources.list.d/ddebs.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y "linux-image-$kernel_version-dbgsym" || \
    sudo apt-get install -y "linux-image-unsigned-$kernel_version-dbgsym"
}

install_dwarf2json
maybe_install_dbgsym || {
  cat > "$out_dir/SYMBOL_BUILD_FAILED.txt" <<TXT
Volatility symbol generation could not find or install a debug vmlinux for $kernel_version.
endpoint.vmem is still a full physical RAM image, but Linux process plugins need matching
Volatility 3 symbols. Re-run this script after installing the kernel dbgsym package.
TXT
  exit 0
}
vmlinux="$(find_vmlinux)"
system_map="/boot/System.map-$kernel_version"
symbol_out="$out_dir/linux-$kernel_version.json.xz"
rm -f "$symbol_out" "$symbol_out.tmp"
ensure_symbol_swap
if [[ -r "$system_map" ]]; then
  if ! dwarf2json linux --elf "$vmlinux" --system-map "$system_map" | xz -T1 > "$symbol_out.tmp"; then
    rm -f "$symbol_out.tmp"
    cat > "$out_dir/SYMBOL_BUILD_FAILED.txt" <<TXT
Volatility symbol generation found $vmlinux but dwarf2json failed on this host.
The most common cause is insufficient RAM. Re-run with more memory or build the
symbol table on a larger Ubuntu host with the same kernel package.
TXT
    exit 0
  fi
else
  if ! dwarf2json linux --elf "$vmlinux" | xz -T1 > "$symbol_out.tmp"; then
    rm -f "$symbol_out.tmp"
    cat > "$out_dir/SYMBOL_BUILD_FAILED.txt" <<TXT
Volatility symbol generation found $vmlinux but dwarf2json failed on this host.
The most common cause is insufficient RAM. Re-run with more memory or build the
symbol table on a larger Ubuntu host with the same kernel package.
TXT
    exit 0
  fi
fi
mv "$symbol_out.tmp" "$symbol_out"
chmod 0444 "$symbol_out"
cat > "$out_dir/volatility-command.txt" <<TXT
vol -f endpoint.vmem --symbol-dirs ./volatility banners.Banners
vol -f endpoint.vmem --symbol-dirs ./volatility linux.pslist
vol -f endpoint.vmem --symbol-dirs ./volatility linux.psaux | grep -i wupdate
vol -f endpoint.vmem --symbol-dirs ./volatility linux.pstree
TXT
