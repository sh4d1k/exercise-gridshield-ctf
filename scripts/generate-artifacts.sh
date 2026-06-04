#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
cd "$PROJECT_ROOT"

out="$PROJECT_ROOT/generated"
if [[ -d "$out" ]]; then
  sudo chmod -R u+rwX "$out" 2>/dev/null || true
  sudo rm -rf "$out"
fi
mkdir -p "$out"/{keys,m1/evidence,m1/cache,m2/ftp,m2/internal/secure_mgmt/keys,m2/internal/secure_mgmt/agent_logs,m3/openvpn/clients,m3/log,m3/ssh,m3/support,attacker-workstation/home/devuser/Desktop,attacker-workstation/home/devuser/.ssh,attacker-workstation/home/devuser/Backups,ctfd}

ssh-keygen -q -t rsa -b 2048 -N 'GridVPN#2026' -C 'gridshield-vpn-access' -f "$out/keys/vpn_access.pem"
ssh-keygen -q -t rsa -b 2048 -N 'Infradev#99' -C 'gridshield-dev-key' -f "$out/keys/dev_key"
cp "$out/keys/vpn_access.pem" "$out/m2/internal/secure_mgmt/keys/vpn_access.pem"
cp "$out/keys/vpn_access.pem.pub" "$out/m3/ssh/authorized_keys"
cp "$out/keys/dev_key" "$out/m3/ssh/dev_key"
cp "$out/keys/dev_key.pub" "$out/attacker-workstation/home/devuser/.ssh/authorized_keys"

cat > "$out/m1/evidence/case_notes.txt" <<'TXT'
INITIAL EVIDENCE ACQUISITION NOTE

Host: CB-FS01 (cbfs01)
Acquisition Time: 2026-05-15 04:10:00 +0530
Evidence Items:
  - endpoint.vmem: full physical RAM image acquired from CB-FS01 during first-response containment
  - archive.enc: encrypted ransomware archive recovered from the affected endpoint
  - ransom_note.txt: ransom demand text collected from the endpoint
Acquisition Type: Full physical RAM image and encrypted file artefact
Purpose: Malware and ransomware triage

First responders preserved the affected host and collected the initial evidence package
after containment of a ransomware incident.

First-response telemetry showed repeated small outbound information transfers from
CB-FS01 during containment. The same activity resumed after a controlled restart
of the affected endpoint, suggesting the responsible artefact may have a
persistence mechanism.

No packet capture is provided with the initial evidence package.
Investigators should begin by analysing the memory image and correlating it with the encrypted archive.
TXT
cat > "$out/m1/evidence/ransom_note.txt" <<'TXT'
GRIDVAULT-FS-LOCKED
A GridVault Bank internal file server was encrypted.
Pay 12.4 BTC to bc1q7xkm3p9nfv2c8wq4rjh5e6dtya0ls3gkpz8mn
Recovery portal: gridvault-recovery-example.onion
TXT
memory_cache_root="$PROJECT_ROOT/generated/cache/m1-memory"
memory_cache_version="${GRIDSHIELD_M1_MEMORY_CACHE_VERSION:-v2}"
memory_cache_key="$(
  {
    printf 'cache_version=%s\n' "$memory_cache_version"
    printf 'memory_mb=%s\n' "${GRIDSHIELD_M1_MEMORY_MB:-512}"
    printf 'kernel=%s\n' "${GRIDSHIELD_M1_ACQ_KERNEL:-5.15.0-125-generic}"
    sha256sum "$PROJECT_ROOT/scripts/build-m1-memory-image.sh"
  } | sha256sum | awk '{print $1}'
)"
memory_cache_dir="$memory_cache_root/$memory_cache_key"
if [[ "${GRIDSHIELD_REBUILD_M1_MEMORY:-0}" != "1" \
      && -s "$memory_cache_dir/endpoint.vmem" \
      && -d "$memory_cache_dir/volatility" ]]; then
  echo "Reused cached M1 memory image: $memory_cache_key"
  cp -a "$memory_cache_dir/endpoint.vmem" "$out/m1/evidence/endpoint.vmem"
  cp -a "$memory_cache_dir/volatility" "$out/m1/evidence/volatility"
else
  echo "Building fresh M1 memory image: $memory_cache_key"
  scripts/build-m1-memory-image.sh "$out/m1/evidence/endpoint.vmem"
  mkdir -p "$memory_cache_dir"
  chmod -R u+rwX "$memory_cache_dir" 2>/dev/null || true
  rm -rf "$memory_cache_dir/endpoint.vmem" "$memory_cache_dir/volatility"
  cp -a "$out/m1/evidence/endpoint.vmem" "$memory_cache_dir/endpoint.vmem"
  cp -a "$out/m1/evidence/volatility" "$memory_cache_dir/volatility"
  chmod -R a-w "$memory_cache_dir" 2>/dev/null || true
fi
chmod -R u+rwX "$out/m1/evidence/volatility" 2>/dev/null || true
cat > "$out/m1/evidence/volatility/cache_manifest.txt" <<TXT
Cache Key: $memory_cache_key
Cache Version: $memory_cache_version
Cache Source: $memory_cache_dir
Force Rebuild: GRIDSHIELD_REBUILD_M1_MEMORY=1
TXT
cat > "$out/m1/cache/run.log" <<'TXT'
2026-05-15T03:00:04Z local cache initialized
2026-05-15T03:00:05Z archive staging complete
TXT
mkdir -p "$out/tmp/archive_src"
cat > "$out/tmp/archive_src/recovery_note.txt" <<'TXT'
CENTRAL BANK INTERNAL FILE SERVER
RANSOMWARE RECOVERY VALIDATION NOTE

Host: cbfs01
Victim Reference: CB-FS01-EP009
Recovered Dataset: supervision,payments,hr

The decrypted files confirm that the ransomware recovery key is valid and that
victim data from cbfs01 was affected.

Recovery validation marker:
CTF{VICTIM_ARCHIVE_DECRYPTED_EP009}

Analyst note:
The victim reference EP009 should be used to correlate this recovered archive
with any malware artefacts or transmitted host activity identified during the
investigation.

First-response observation:
Endpoint telemetry preserved during containment indicated a small outbound
transmission from cbfs01 at approximately 20-second intervals. The receiving
system and credentials were not recovered from this archive.
TXT
cat > "$out/tmp/archive_src/affected_files_manifest.csv" <<'CSV'
case_id,host,victim_reference,dataset,file_name,status
GS-2026-015,cbfs01,CB-FS01-EP009,supervision,supervision_records.csv,recovered
GS-2026-015,cbfs01,CB-FS01-EP009,payments,payment_ops_extract.csv,recovered
GS-2026-015,cbfs01,CB-FS01-EP009,hr,staff_directory_extract.csv,recovered
CSV
cat > "$out/tmp/archive_src/sample_victim_record.txt" <<'TXT'
Sample Recovered Victim Data

Host: cbfs01
Victim Reference: CB-FS01-EP009
Data Groups: supervision, payments, hr

This sample confirms that the encrypted archive contained operational victim data.
TXT
tar -czf "$out/tmp/archive.tar.gz" -C "$out/tmp/archive_src" .
openssl enc -aes-256-cbc -pbkdf2 -salt -k '4a7f3c91b2d0e865' -in "$out/tmp/archive.tar.gz" -out "$out/m1/cache/archive.enc"
cp "$out/m1/cache/archive.enc" "$out/m1/evidence/archive.enc"
rm -rf "$out/tmp"

cat > "$out/m2/ftp/README_RESTORE.txt" <<'TXT'
NovaSec backup staging area. Operational files restored by nsadmin only.

The protected operations archive and the web console were both assigned
from the same emergency password rotation. Restore operators should
recover the archive password first, then validate the same password
against the web console.
TXT
cat > "$out/m2/ftp/c2_instructions.asc" <<'TXT'
Simulated encrypted dead-drop note.
Restore rotation hint: nsadmin used the May 2024 NovaSec emergency-password pattern.
The protected operations ZIP and the 2083 web console share the same weak
operational password. Crack the ZIP with the staged candidate list first,
then test the recovered password on the web console.
VPN relay public evidence: 192.0.2.10 / Blue Transit VPN relay
TXT
{
  for base in NovaSec N0vaSec Novasec NovaSEC NsAdmin NSAdmin SiteBackup Backup Restore RestoreOps NovaOps C2Ops; do
    for tail in 2024 2025 2026 24 25 26 '!2024' '#2024' '@2024'; do
      printf '%s%s\n' "$base" "$tail"
    done
  done
  printf '%s\n' 'N0v@S3c!2024'
  for candidate in \
    NovaSecRestore24 NovaSecRestore2024 RestorePortal2024 RestorePortal24 \
    NsConsole2024 NsConsole24 NSPanel2024 NSPanel24 \
    BackupConsole2024 BackupConsole24 SiteOps2024 SiteOps24 \
    BlueTransit2024 BlueTransit24 GridOps2024 GridOps24 \
    EmergencyRestore2024 EmergencyRestore24 C2Restore2024 C2Restore24 \
    NovaSecEmergency2024 NovaSecEmergency24; do
    printf '%s\n' "$candidate"
  done
} > "$out/m2/ftp/ops_candidates.txt"
mkdir -p "$out/tmp/ops/admin_notes"
cat > "$out/tmp/ops/admin_notes/cpanel_access.txt" <<'TXT'
cPanel-style admin: nsadmin / N0v@S3c!2024
Port: 2083
CTF{ZIP_UNLOCKED_CPANEL_HIDDEN_SECURE_MGMT}
TXT
cat > "$out/tmp/ops/hidden_paths.txt" <<'TXT'
/secure_mgmt/       - internal panel landing
/db_admin/          - database management
/filemanager.php    - authenticated internal file manager
TXT
cat > "$out/tmp/ops/deploy_checklist.txt" <<'TXT'
Keep NovaSec homepage boring. Keep real admin tools hidden underneath.
TXT
(cd "$out/tmp/ops" && zip -qr -P 'N0v@S3c!2024' "$out/m2/ftp/encrypted_ops.zip" .)
rm -rf "$out/tmp"
cat > "$out/m2/internal/secure_mgmt/agent_logs/ep-009.log" <<'TXT'
ep-009 first seen 2026-05-03, C2 public evidence 198.51.100.20
TXT

cat > "$out/m3/log/openvpn.log" <<'TXT'
2026-05-15 03:43:59 198.51.100.20:51234 [operator] Peer Connection Initiated
2026-05-15 03:44:11 TLS: tls_process: killed expiry or error
2026-05-15 03:44:14 198.18.45.23:51234 [operator] Peer Connection Initiated
# CTF{VPN_DROPOUT_REAL_IP_198_18_45_23_EXPOSED}
2026-05-15 03:44:41 198.51.100.20:51234 [operator] Peer Connection Initiated
TXT
cat > "$out/m3/log/auth.log" <<'TXT'
2026-05-15 03:44:18 vpn-gw sshd[2184]: Accepted publickey for operator from 198.18.45.23 port 51234 ssh2
TXT
cat > "$out/m3/support/README_RELAY_SUPPORT.md" <<'TXT'
# Blue Transit Relay Support Notes

Host context: blue-transit-relay / relay-01
Audience: authorised relay support staff and infrastructure administrators

This note is kept on the Blue Transit relay for support staff who need to
investigate operator reconnect problems, relay dropouts, or emergency access
issues.

Primary log locations:

- /var/log/openvpn.log
  Review TLS expiry, session timeout, peer reconnect, and relay dropout events.
  Check whether a raw operator-side address appears briefly during a failure
  window.

- /var/log/auth.log
  Corroborate the same time window with SSH authentication activity and accepted
  public key events.

Operator profile recovery notes:

- /etc/openvpn/config.hash
  Validation hash for the emergency operator profile passphrase.

- /etc/openvpn/passphrase_candidates.txt
  Local support candidate list for profile passphrase recovery.

- /etc/openvpn/clients/operator.ovpn.enc
  Encrypted operator profile. After recovering the passphrase, decrypt it
  with OpenSSL using aes-256-cbc and pbkdf2.

- /home/infraadmin/.ssh/dev_key
  Emergency workstation key. Review the decrypted operator profile before
  using this key.
TXT
mkdir -p "$out/m3/support/incident_notes"
cat > "$out/m3/support/incident_notes/relay_dropouts.md" <<'TXT'
# Relay Dropout Review Queue

Open item: review the 2026-05-15 03:44 UTC reconnect window.

Start with /var/log/openvpn.log and correlate any raw operator-side address
with /var/log/auth.log before using the encrypted operator profile.
TXT
openssl passwd -apr1 -salt gs99 'Infradev#99' > "$out/m3/openvpn/config.hash"
{
  for base in InfraDev Infradev GridInfra BlueTransit RelayOps DevStation OperatorProfile EmergencyVPN CoreRelay AccessOps; do
    for tail in 2024 2025 2026 24 25 26 '#2024' '#2025' '#2026' '99'; do
      printf '%s%s\n' "$base" "$tail"
    done
  done
  printf '%s\n' 'Infradev#99'
  for candidate in RelaySupport99 OperatorEmergency2026 GridRelay#2026 BlueOps99 DevStationEmergency; do
    printf '%s\n' "$candidate"
  done
} > "$out/m3/openvpn/passphrase_candidates.txt"
cat > "$out/tmp_operator.ovpn" <<'TXT'
client
remote 192.0.2.10 1194 udp
# Emergency SSH: user=devuser, keyfile=dev_key
# Lab mapping: 198.18.45.23 -> devstation.gridshield.local / 10.1.1.15
# CTF{OVPN_CONFIG_DEVUSER_DEV_KEY_INFRADEV99}
TXT
openssl enc -aes-256-cbc -pbkdf2 -salt -k 'Infradev#99' -in "$out/tmp_operator.ovpn" -out "$out/m3/openvpn/clients/operator.ovpn.enc"
rm "$out/tmp_operator.ovpn"

wallet='bc1q7xkm3p9nfv2c8wq4rjh5e6dtya0ls3gkpz8mn'
wallet_md5="$(printf '%s' "$wallet" | md5sum | awk '{print $1}')"
echo "$wallet" > "$out/attacker-workstation/home/devuser/Desktop/payment_wallet.txt"
cat > "$out/attacker-workstation/home/devuser/Desktop/ops_notes.txt" <<TXT
NovaSec C2: 198.51.100.20 / internal service mapping
Blue Transit VPN: 192.0.2.10 / relay-01
Operator workstation: 198.18.45.23 / devstation
TXT
cat > "$out/attacker-workstation/home/devuser/Desktop/recovery_notes.txt" <<TXT
Cleanup reminder - case bundle

Payment wallet receipt is on the desktop. Do not paste the wallet into ops notes.

ID scan wrapper:
use the wallet string exactly as the PDF password.

Contract mail export:
use md5(wallet) as the PDF password.
Regenerate with: printf %s "\$wallet" | md5sum

Working copies were moved into the workstation backup before cleanup.
If recovery is needed, carve the backup image and test the PDF passwords.
TXT
cat > "$out/attacker-workstation/home/devuser/.bash_history" <<'TXT'
ssh nsadmin@10.1.1.20
ssh infraadmin@10.1.1.10
ssh devuser@10.1.1.15
find /home/devuser -type f -size +10M
TXT
cat > "$out/attacker-workstation/home/devuser/.ssh/known_hosts" <<'TXT'
10.1.1.20 ssh-rsa SYNTHETIC_M2
10.1.1.10 ssh-rsa SYNTHETIC_M3
TXT
work="$(mktemp -d)"
mnt="$(mktemp -d)"
cleanup_m4() {
    mountpoint -q "$mnt" && sudo umount "$mnt" || true
    rm -rf "$work" "$mnt"
}
trap cleanup_m4 EXIT
make_pdf() {
  local out="$1" title="$2" body="$3" flag="$4"
  python3 - "$out" "$title" "$body" "$flag" <<'PY'
from pathlib import Path
import sys

out, title, body, flag = sys.argv[1:5]
lines = [title, "", body, "", flag]

def esc(s):
    return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")

stream_lines = ["BT", "/F1 12 Tf", "72 760 Td"]
first = True
for line in lines:
    if first:
        stream_lines.append(f"({esc(line)}) Tj")
        first = False
    else:
        stream_lines.append("0 -18 Td")
        stream_lines.append(f"({esc(line)}) Tj")
stream_lines.append("ET")
stream = "\n".join(stream_lines).encode("ascii")

objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
]
pdf = bytearray(b"%PDF-1.4\n")
offsets = [0]
for i, obj in enumerate(objects, 1):
    offsets.append(len(pdf))
    pdf.extend(f"{i} 0 obj\n".encode("ascii"))
    pdf.extend(obj)
    pdf.extend(b"\nendobj\n")
xref = len(pdf)
pdf.extend(f"xref\n0 {len(objects)+1}\n0000000000 65535 f \n".encode("ascii"))
for off in offsets[1:]:
    pdf.extend(f"{off:010d} 00000 n \n".encode("ascii"))
pdf.extend(f"trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode("ascii"))
Path(out).write_bytes(bytes(pdf))
PY
}
make_pdf "$work/fictional_operator_id_source.pdf" \
  "Fictional Operator Identity Record" \
  "Training document for Exercise Gridshield. All names, identifiers, and organisations are fictional." \
  "CTF{CASE_CLOSED_OPERATOR_ID_RECOVERED}"
make_pdf "$work/fictional_service_contract_source.pdf" \
  "Fictional Service Contract Export" \
  "Training document for Exercise Gridshield. This contract is synthetic and unrelated to real people or entities." \
  "CTF{CASE_CLOSED_CONTRACT_RECOVERED_MD5_WALLET}"
qpdf --encrypt "$wallet" "$wallet" 256 -- "$work/fictional_operator_id_source.pdf" "$work/fictional_operator_id.pdf"
qpdf --encrypt "$wallet_md5" "$wallet_md5" 256 -- "$work/fictional_service_contract_source.pdf" "$work/fictional_service_contract.pdf"
echo 'wallet-derived PDF password' > "$work/wallet_source.txt"
echo 'contract password uses md5(payment wallet)' > "$work/contract_password_source.txt"
img="$out/attacker-workstation/home/devuser/Backups/workstation_home_backup_2026-05-16.img"
dd if=/dev/zero of="$img" bs=1M count=32 status=none
mkfs.ext4 -F "$img" >/dev/null
sudo mount -o loop "$img" "$mnt"
sudo mkdir -p "$mnt/home/devuser/deleted_case_bundle" "$mnt/home/devuser/notes"
sudo cp "$work/fictional_operator_id.pdf" "$mnt/home/devuser/deleted_case_bundle/fictional_operator_id.pdf"
sudo cp "$work/fictional_service_contract.pdf" "$mnt/home/devuser/deleted_case_bundle/fictional_service_contract.pdf"
sudo cp "$work/wallet_source.txt" "$mnt/home/devuser/notes/wallet_source.txt"
sudo cp "$work/contract_password_source.txt" "$mnt/home/devuser/notes/contract_password_source.txt"
sync
sudo rm -f "$mnt/home/devuser/deleted_case_bundle/fictional_operator_id.pdf" "$mnt/home/devuser/deleted_case_bundle/fictional_service_contract.pdf"
sudo rmdir "$mnt/home/devuser/deleted_case_bundle" || true
sync
sudo umount "$mnt"
rmdir "$mnt"
sudo chown "$(id -u):$(id -g)" "$img"
rm -rf "$work"
trap - EXIT

cat > "$out/ctfd/flags.txt" <<'TXT'
CTF{SCRIPT_RECOVERED_RUNTIME_CREDS_NOT_HARDCODED}
CTF{VICTIM_ARCHIVE_DECRYPTED_EP009}
CTF{PERSISTENCE_SYSTEMD_WUPDATE_SERVICE}
CTF{ZIP_UNLOCKED_CPANEL_HIDDEN_SECURE_MGMT}
CTF{DIRB_FOUND_SECURE_MGMT_AND_DB_ADMIN}
CTF{SQLI_AGENT_ACTIVITY_DUMP_EP009}
CTF{VPN_DROPOUT_REAL_IP_198_18_45_23_EXPOSED}
CTF{OVPN_CONFIG_DEVUSER_DEV_KEY_INFRADEV99}
CTF{CASE_CLOSED_OPERATOR_ID_RECOVERED}
CTF{CASE_CLOSED_CONTRACT_RECOVERED_MD5_WALLET}
TXT
find "$out" -type f -print0 | sort -z | xargs -0 sha256sum > "$out/SHA256SUMS"
