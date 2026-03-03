# Installation Guide

This guide walks through building and running `slurm-qiskit-cluster` from scratch on any Linux host, including WSL2.

---

## Contents

- [Prerequisites](#prerequisites)
- [Installing Podman](#installing-podman)
- [WSL2-specific setup](#wsl2-specific-setup)
- [Clone the repository](#clone-the-repository)
- [Configure the environment](#configure-the-environment)
- [Configure credentials](#configure-credentials)
- [Build the images](#build-the-images)
- [Build the shared environment](#build-the-shared-environment)
- [Start the cluster](#start-the-cluster)
- [Verify the installation](#verify-the-installation)
- [IBM Quantum account types](#ibm-quantum-account-types)
- [Updating packages](#updating-packages)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, confirm you have the following on your host:

- Linux (bare metal, VM, or WSL2) — Rocky Linux 9, Fedora, Ubuntu 22.04+, or RHEL 9 recommended
- Podman 4.0 or later
- `podman compose`
- Git 2.13 or later (submodule support)
- 20 GB free disk space (images + shared pyenv are large)
- NVIDIA GPU with drivers (optional — required only for g1 / qg1 nodes)

Run the prerequisite check at any time:

```bash
./setup/00-check-prereqs.sh
```

---

## Installing Podman

### Fedora / Rocky Linux 9 / RHEL

```bash
sudo dnf install podman podman-compose
```

### Ubuntu 22.04+

```bash
sudo apt update
sudo apt install podman
pip install podman-compose
```

### WSL2 (any distro)

Podman runs natively inside WSL2 — install using the distro instructions above. No Docker Desktop required.

Official Podman installation documentation: https://podman.io/docs/installation

---

## WSL2-specific setup

If you are running on WSL2 with an NVIDIA GPU, you need the NVIDIA Container Toolkit and GPU passthrough configured before the g1 node will work.

### 1. Ensure WSL2 NVIDIA drivers are installed on Windows

Install or update the NVIDIA driver on Windows (not inside WSL). The Windows driver provides `/usr/lib/wsl/lib` inside WSL2 automatically.

Verify inside WSL2:

```bash
ls /usr/lib/wsl/lib/libcuda*
# Should list libcuda.so and related files
```

### 2. Verify /dev/dxg exists

```bash
ls /dev/dxg
```

If this file is missing, your WSL2 kernel or Windows NVIDIA driver needs updating. See:
https://docs.microsoft.com/en-us/windows/ai/directml/gpu-cuda-in-wsl

---

## Clone the repository

Clone with `--recurse-submodules` to initialise `shared/qrmi` and `shared/spank-plugins` in one step:

```bash
git clone --recurse-submodules https://github.com/<you>/slurm-qiskit-cluster.git
cd slurm-qiskit-cluster
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

Verify submodules are populated:

```bash
ls shared/qrmi/Cargo.toml          # should exist
ls shared/spank-plugins/plugins/   # should exist
```

---

## Configure the environment

Copy the example environment file and review the values:

```bash
cp .env.example .env
```

Open `.env` and confirm or update:

```bash
# The Slurm git tag to build from — must match across all images
SLURM_TAG=slurm-23-11-9-1

# Image tag for all built images
IMAGE_TAG=latest

# Build versions — change only if you need to upgrade
GOSU_VERSION=1.17
MY_PMIX_VERSION=4.2.9
OPENMPI_VERSION=4.1.6

# CUDA version (gpu and quantum-gpu stages only)
CUDA_VERSION=12-9
```

The `SLURM_TAG` must correspond to a valid tag in https://github.com/SchedMD/slurm/tags. The value above (`slurm-23-11-9-1`) is the confirmed working version for this repo.

---

## Configure credentials

QRMI uses a JSON config file to define your quantum backends. The file contains API keys and must never be committed to version control.

Run the credential setup script:

```bash
./setup/03-configure-credentials.sh
```

This copies `cluster/config/qrmi_config.json.example` to `cluster/config/qrmi_config.json` and opens it for editing.

### IBM Quantum account types

The config supports three backend types. Which ones you can use depends on your account:

**Free / Open Plan (most users)**

Use `qiskit-runtime-service`. You need:
- An IBM Quantum account: https://quantum.cloud.ibm.com
- Your IAM API key (found in your account settings)
- Your IQP instance CRN (found in your IBM Cloud account)

The endpoint URLs are standard and pre-filled in the example:
```
QRMI_IBM_QRS_ENDPOINT: https://quantum.cloud.ibm.com/api/v1
QRMI_IBM_QRS_IAM_ENDPOINT: https://iam.cloud.ibm.com
```

**Reserved / Paid contracts only**

Use `direct-access`. This requires a dedicated IBM Quantum contract and provides AWS S3 credentials for job data transfer. If you have a free or standard account, remove this stanza from your config entirely.

**Pasqal**

Use `pasqal-cloud`. Requires a Pasqal Cloud account and endpoint URL.

You can define multiple backends of the same type (e.g. three `qiskit-runtime-service` stanzas pointing to different instances). Remove any stanzas for backends you do not have access to.

After editing, the script will warn you if any `<YOUR ...>` placeholders remain unfilled.

---

## Build the images

```bash
./setup/01-build-images.sh
```

This builds all Dockerfile targets: `builder`, `control`, `compute-base`, `quantum`, `gpu`, and `quantum-gpu`.

Expected build time: 20–40 minutes depending on your connection (Slurm, PMIx, and OpenMPI are all compiled from source).

To force a full rebuild without layer cache:

```bash
./setup/01-build-images.sh --no-cache
```

---

## WSL2: Allow Podman to access /dev/dxg (GPU only)

**This step is required only if you have an NVIDIA GPU on WSL2 and want to use the g1 node. It must be done after running `01-build-images.sh`** because that step populates `/etc/containers/containers.conf`.

Edit the file:

```bash
sudo vi /etc/containers/containers.conf
```

Find the existing `[containers]` section — do not add a new one — and add the `devices` line inside it:

```toml
[containers]
devices = ["/dev/dxg"]
```

If a `devices` line already exists in that section, add `/dev/dxg` to it:

```toml
devices = ["/dev/dxg", "/dev/other-device"]
```

Verify the file parses correctly:

```bash
podman info > /dev/null && echo "OK"
```

---

## Build the shared environment

The builder container populates `./shared` with:
- `/shared/pyenv` — the full quantum Python virtual environment
- `/shared/spank-plugins/plugins/spank_qrmi/build/spank_qrmi.so` — the SPANK plugin

```bash
./setup/02-build-shared.sh
```

Expected time: 10–20 minutes (pyscf, jax, and ffsim are large packages).

The build is skipped if `/shared/pyenv` already exists. To force a rebuild:

```bash
./setup/02-build-shared.sh --force
```

### What gets installed in /shared/pyenv

The full pinned package list is in `requirements/pyenv-frozen.txt`. Key packages:

| Package | Version | Purpose |
|---|---|---|
| qiskit | 2.3.0 | Quantum circuit building and transpilation |
| qrmi | 0.10.1 | Quantum Resource Management Interface (Rust extension, built from source) |
| qiskit-ibm-runtime | 0.45.1 | IBM Quantum backend access |
| qiskit-addon-sqd | 0.12.1 | Sample-based quantum diagonalization |
| ffsim | 0.0.67 | Fast fermionic simulation |
| pyscf | 2.12.1 | Quantum chemistry |
| jax / jaxlib | 0.9.0.1 | Accelerated numerical computing |
| pulser | 1.6.6 | Pasqal neutral atom support |
| mpi4py | 4.1.1 | MPI Python bindings |

---

## Start the cluster

```bash
./setup/04-start-cluster.sh
```

The script runs pre-flight checks (pyenv, SPANK plugin, credentials) before starting the cluster and waits for `slurmctld` to become ready. It then prints the cluster node state and confirms the SPANK `--qpu` option is visible.

To stop the cluster:

```bash
podman compose -f cluster/docker-compose.yml down
```

To view logs:

```bash
podman compose -f cluster/docker-compose.yml logs -f
podman logs -f slurmctld
```

---

## Verify the installation

```bash
# Basic verification (no GPU or credentials required)
./setup/05-verify.sh

# Include GPU tests (requires g1 with NVIDIA GPU)
./setup/05-verify.sh --gpu

# Include QRMI connectivity test (requires valid credentials and network access)
./setup/05-verify.sh --qrmi

# Full verification
./setup/05-verify.sh --gpu --qrmi
```

A passing run confirms: containers up, Slurm responding, SPANK plugin loaded, `/shared/pyenv` mounted and importable on all nodes, Qiskit Bell state circuit executes correctly, and batch job submission works end to end.

---

## Updating packages

Because the quantum stack lives in `/shared/pyenv` on the host rather than baked into the images, you can update packages without rebuilding any images:

```bash
# Rebuild /shared/pyenv with updated packages
./setup/02-build-shared.sh --force
```

Then restart the cluster:

```bash
podman compose -f cluster/docker-compose.yml restart
```

To update pinned versions, edit `requirements/pyenv-frozen.txt` before running `--force`.

---

## Troubleshooting

**slurmctld does not become ready**

```bash
podman logs slurmctld
podman logs slurmdbd
podman logs mysql
```

The most common cause is slurmdbd failing to connect to MySQL before slurmctld starts. The cluster will self-recover — wait 30 seconds and check `sinfo` again.

**SPANK --qpu option not visible in sbatch --help**

The SPANK plugin failed to load. Check:
```bash
podman exec q1 bash -lc "ls -lh /shared/spank-plugins/plugins/spank_qrmi/build/spank_qrmi.so"
podman exec q1 bash -lc "cat /etc/slurm/plugstack.conf"
```

If the `.so` is missing, run `./setup/02-build-shared.sh --force`.

**qrmi import fails on q1**

```bash
podman exec q1 bash -lc "python3 -c 'import qrmi'"
```

If you see a Rust/ABI error, the qrmi wheel was built against a different system ABI. Run `./setup/02-build-shared.sh --force` to rebuild the wheel inside the builder container.

**GPU not detected on g1**

```bash
podman exec g1 bash -lc "python3 -c 'import cupy; print(cupy.cuda.runtime.getDeviceCount())'"
```

On WSL2, verify `/usr/lib/wsl/lib` is bind-mounted and `/dev/dxg` exists on the host.

**Disk space**

Images + `/shared/pyenv` together require approximately 15–20 GB. Check available space:

```bash
df -h .
podman system df
```

To reclaim space from old images:

```bash
podman system prune
```
