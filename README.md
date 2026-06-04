# Exercise Gridshield

Exercise Gridshield is a self-contained incident-response CTF about a ransomware
and data-extortion investigation.

The public release is a single local Docker Compose setup:

```text
M1 compromised endpoint -> M2 C2 repository -> M3 relay -> M4 attacker workstation
```

The original event used team VMs and a separate VPN layer. This public version
removes that event-specific network layer and exposes the lab through localhost
ports while keeping the same evidence-led investigation flow inside Docker.

## Quick Start

On a Linux host with Docker, Docker Compose, OpenSSL, qpdf, John, zip, unzip,
TestDisk/PhotoRec, QEMU, and Python 3:

```bash
chmod +x scripts/*.sh
./scripts/install-requirements.sh
./scripts/build.sh
./scripts/test.sh
```

### Host prerequisites

The first step is to install host prerequisites before building the challenge.
On Debian/Ubuntu hosts, install the packaged dependencies from
`requirements.txt` with:

```bash
chmod +x scripts/install-requirements.sh
./scripts/install-requirements.sh
```

If you want to preview the packages without installing them:

```bash
./scripts/install-requirements.sh --dry-run
```

If your VM or host uses a different Linux distribution, install equivalent
packages manually.

Start point for participants:

```bash
ssh investigator@127.0.0.1 -p 2221
```

Password:

```text
Inv3st!gate2024
```

If Kali is a separate VM on the same host-only network, replace `127.0.0.1`
with the challenge Linux VM address. For example:

```bash
ssh investigator@192.168.56.11 -p 2221
```

Initial evidence is mounted in M1 at:

```text
/evidence/
```

To create a lightweight participant package after building:

```bash
./scripts/export-participant-pack.sh
```

The exported zip omits the large RAM image by default. Participants collect
`endpoint.vmem` from the running M1 container through the SSH handoff.

## Local Port Map

| Service | Local address | Container target |
| --- | --- | --- |
| M1 SSH | `127.0.0.1:2221` | `cbfs01:22` |
| M2 web | `127.0.0.1:8080` | `m2:80` |
| M2 cPanel-style web | `127.0.0.1:2083` | `m2:2083` |
| M2 FTP control | `127.0.0.1:2121` | `m2:21` |
| M3 SSH | `127.0.0.1:2223` | `m3:22` |
| M4 SSH | `127.0.0.1:2224` | `m4:22` |

Inside the lab, DNS still resolves public-sim evidence addresses such as
`ftp.gridvault-records.test -> 198.51.100.20`. M1 is attached to the public-sim Docker
network, so malware traffic and packet captures still show the WAN-looking C2
address.

## Repository Layout

```text
participant/      participant brief, rules, and connection guide
organiser/        solution guide, scoring, flags, troubleshooting
ctfd/             optional CTFd challenge-as-code files
infra/            Docker Compose and local infrastructure
src/              challenge service/source files
  src/attacker-workstation  M4 attacker workstation source
scripts/          build, test, reset, and artifact generation
generated/        generated evidence and runtime artifacts, gitignored
End_files/        public-safe final evidence generation notes
```

## Public Safety Notes

- Final PDFs are generated as fictional synthetic training documents.
- Event-specific VPN material and private deployment keys are not included.
- CTFd files are optional and are not required to run the challenge locally.
