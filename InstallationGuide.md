# Installation Guide

This guide walks through building and running `slurm-qiskit-cluster` from scratch on any Linux host, including WSL2.

---

## Contents

- [Prerequisites](#prerequisites)
- [Installing Podman](#installing-podman)
- [Bare-metal GPU setup (NVIDIA only)](#bare-metal-gpu-setup-nvidia-only)
- [WSL2-specific setup](#wsl2-specific-setup)
- [Clone the repository](#clone-the-repository)
- [Configure the environment](#configure-the-environment)
- [Configure system hardware](#configure-system-hardware)
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
- **NVIDIA GPU with CUDA support** (optional — required only for the `g1` and `qg1` nodes; see [GPU support](#gpu-support) below)

After cloning the repository, you can verify prerequisites with:

```bash
./setup/00-check-prereqs.sh
```

### GPU support

GPU acceleration in this cluster is **optional**. The `c1`, `c2`, `q1`, and `login` nodes run without any GPU. Only the `g1` and `qg1` nodes require a GPU:

- `g1` — GPU postprocessing node (CuPy, Dice eigensolver)
- `qg1` — GPU-accelerated Aer simulation node (qiskit-aer-gpu)

**Only NVIDIA GPUs with CUDA are supported.** AMD, Intel, and other GPU vendors are not currently supported. Specifically, this cluster has been tested with:

- NVIDIA driver 576.40 or later
- CUDA 12.9
- CuPy 14.0.1 (`cupy-cuda12x`)

If you do not have an NVIDIA GPU, simply omit all `--gpu` and `--quantum-gpu` flags throughout this guide. The `g1` and `qg1` containers will still start but GPU-dependent workloads will fail inside them. All other cluster functionality — Slurm scheduling, Qiskit simulation, QRMI/quantum access — works fully without a GPU.

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

## Bare-metal GPU setup (NVIDIA only)

> **Skip this section if you do not have an NVIDIA GPU, or if you are running on WSL2.**

On bare-metal Linux, Podman uses the [Container Device Interface (CDI)](https://github.com/cncf-tags/container-device-interface) to inject the GPU into containers. You need to install the NVIDIA Container Toolkit and generate a CDI manifest once before starting the cluster.

### 1. Install the NVIDIA Container Toolkit

#### Fedora / Rocky Linux 9 / RHEL

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
    | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
sudo dnf install -y nvidia-container-toolkit
```

#### Ubuntu 22.04+

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update && sudo apt install -y nvidia-container-toolkit
```

### 2. Generate the CDI manifest

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

This scans your installed NVIDIA driver and creates `/etc/cdi/nvidia.yaml`, which tells Podman how to inject the GPU into containers. The command produces several `WARN` lines for optional components (X11, Wayland, MPS sockets) — these are harmless.

### 3. Verify

```bash
nvidia-ctk cdi list
# Expected output: nvidia.com/gpu=0  (or similar for your GPU index)
```

Re-run `nvidia-ctk cdi generate` any time you update your NVIDIA driver.

---

## WSL2-specific setup

### Without a GPU

No additional setup is required. Proceed directly to [Clone the repository](#clone-the-repository).

### With an NVIDIA GPU

If you are running on WSL2 with an NVIDIA GPU and want to use the `g1` or `qg1` nodes, you need the NVIDIA Container Toolkit and GPU passthrough configured before those nodes will work.

#### 1. Ensure WSL2 NVIDIA drivers are installed on Windows

Install or update the NVIDIA driver on Windows (not inside WSL). The Windows driver provides `/usr/lib/wsl/lib` inside WSL2 automatically.

Verify inside WSL2:

```bash
ls /usr/lib/wsl/lib/libcuda*
# Should list libcuda.so and related files
```

#### 2. Verify /dev/dxg exists

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

First, verify that all prerequisites are met:

```bash
./setup/00-check-prereqs.sh
```

Then copy the example environment file and review the values:

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

# CUDA version and CPU count — set automatically by 00b-configure-system.sh
# You can override them here if auto-detection gives the wrong result
CUDA_VERSION=12-9
SLURM_CPUS_PER_NODE=2
```

The `SLURM_TAG` must correspond to a valid tag in https://github.com/SchedMD/slurm/tags. The value above (`slurm-23-11-9-1`) is the confirmed working version for this repo.

`CUDA_VERSION` and `SLURM_CPUS_PER_NODE` are updated automatically when you run `./setup/00b-configure-system.sh` in the next step. You only need to edit them manually if auto-detection produces the wrong value.

---

## Configure system hardware

The cluster configuration files (`slurm.conf`, `gres.conf`, `docker-compose.yml`) contain hardware-specific values — CPU count, memory, GPU model, and GPU device path — that differ between machines. These files are **not committed to the repository**. Instead, they are generated from templates by the following script:

```bash
./setup/00b-configure-system.sh
```

Run this once after copying `.env`. The script detects your hardware automatically and renders the three config files. It will show you the resolved values and ask for confirmation before writing anything.

### What it detects

| Value | Source | Files updated |
|---|---|---|
| Logical CPU count | `lscpu` | `slurm.conf`, `.env` |
| CPU topology (sockets, cores, threads) | `lscpu` | `slurm.conf` |
| Usable RAM (95% of total) | `/proc/meminfo` | `slurm.conf` |
| GPU model slug (e.g. `rtx2080ti`) | `nvidia-smi` | `slurm.conf`, `gres.conf` |
| GPU device path (`/dev/dxg` on WSL2, `/dev/nvidia0` on bare metal) | `/dev/dxg` presence + `nvidia-smi` | `gres.conf`, `docker-compose.yml` |
| WSL2 `/usr/lib/wsl/lib` bind-mount | `/dev/dxg` presence | `docker-compose.yml` |
| CUDA version suffix (e.g. `12-9`) | `nvidia-smi` header | `.env` |

### Options

```bash
./setup/00b-configure-system.sh             # auto-detect everything
./setup/00b-configure-system.sh --dry-run   # show values, write nothing
./setup/00b-configure-system.sh --no-gpu    # skip GPU detection (no GPU on this host)
```

### Re-running

The script is safe to re-run — it overwrites the generated files each time. Re-run it if you move the repo to a different machine, change hardware, or edit any of the `.template` files.

### Templates

The three template files are tracked in the repository and contain `@@PLACEHOLDER@@` tokens:

```
cluster/config/slurm.conf.template
cluster/config/gres.conf.template
cluster/docker-compose.yml.template
```

The generated files (`slurm.conf`, `gres.conf`, `docker-compose.yml`) are listed in `.gitignore`. If you need to adjust Slurm policy, partition layout, or other non-hardware settings, edit the corresponding `.template` file and re-run the script.

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

After the cluster is started, the config file must also be copied into the running containers:

```bash
podman cp cluster/config/qrmi_config.json slurmctld:/etc/slurm/qrmi_config.json
podman cp cluster/config/qrmi_config.json q1:/etc/slurm/qrmi_config.json
```

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

## WSL2: Allow Podman to access /dev/dxg (NVIDIA GPU only)

> **Skip this section if you do not have an NVIDIA GPU.**

This step is required only if you have an NVIDIA GPU on WSL2 and want to use the `g1` or `qg1` nodes. It must be done after running `01-build-images.sh` because that step populates `/etc/containers/containers.conf`.

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

### Without a GPU

```bash
./setup/02-build-shared.sh
```

### With an NVIDIA GPU (CUDA)

Pass `--gpu` to install CuPy (for `g1`), `--quantum-gpu` to install qiskit-aer-gpu (for `qg1`), or both:

```bash
./setup/02-build-shared.sh --gpu                    # g1 only
./setup/02-build-shared.sh --quantum-gpu            # qg1 only
./setup/02-build-shared.sh --gpu --quantum-gpu      # both
```

CuPy (`cupy-cuda12x==14.0.1`) and qiskit-aer-gpu are installed into `/shared/pyenv` rather than baked into the images. They are present on all nodes but only functional on `g1` and `qg1` respectively, where the GPU and CUDA libraries are available. **AMD, Intel, and other GPU vendors are not supported — both packages require NVIDIA CUDA.**

Expected time: 10–20 minutes (pyscf, jax, and ffsim are large packages).

The build is skipped if `/shared/pyenv` already exists. To force a rebuild:

```bash
./setup/02-build-shared.sh --force                       # no GPU
./setup/02-build-shared.sh --force --gpu                 # with CuPy (g1)
./setup/02-build-shared.sh --force --quantum-gpu         # with qiskit-aer-gpu (qg1)
./setup/02-build-shared.sh --force --gpu --quantum-gpu   # both
```

### Available flags

| Command | Effect |
|---|---|
| `./setup/02-build-shared.sh` | Full build, no GPU packages |
| `./setup/02-build-shared.sh --gpu` | Full build + CuPy for `g1` (NVIDIA CUDA only) |
| `./setup/02-build-shared.sh --quantum-gpu` | Full build + qiskit-aer-gpu for `qg1` (NVIDIA CUDA only) |
| `./setup/02-build-shared.sh --gpu --quantum-gpu` | Full build + CuPy + qiskit-aer-gpu |
| `./setup/02-build-shared.sh --packages-only` | pip packages only, skip qrmi + SPANK plugin build |
| `./setup/02-build-shared.sh --packages-only --gpu` | pip packages + CuPy, skip qrmi + SPANK plugin build |
| `./setup/02-build-shared.sh --packages-only --quantum-gpu` | pip packages + qiskit-aer-gpu, skip qrmi + SPANK plugin build |
| `./setup/02-build-shared.sh --force --gpu --quantum-gpu` | Full rebuild from scratch + CuPy + qiskit-aer-gpu |

### What gets installed in /shared/pyenv

The full pinned package list is in `requirements/pyenv-frozen.txt`. Key packages:

| Package | Version | Purpose |
|---|---|---|
| qiskit | 2.3.0 | Quantum circuit building and transpilation |
| qrmi | 0.11.0 | Quantum Resource Management Interface (Rust extension, built from source) |
| qiskit-ibm-runtime | 0.45.1 | IBM Quantum backend access |
| qiskit-addon-sqd | 0.12.1 | Sample-based quantum diagonalization |
| ffsim | 0.0.67 | Fast fermionic simulation |
| pyscf | 2.12.1 | Quantum chemistry |
| jax / jaxlib | 0.9.0.1 | Accelerated numerical computing |
| pulser | 1.6.6 | Pasqal neutral atom support |
| mpi4py | 4.1.1 | MPI Python bindings |
| cupy-cuda12x | 14.0.1 | GPU computing via CUDA (**NVIDIA only**, installed with `--gpu`) |
| qiskit-aer-gpu | latest | GPU-accelerated Aer simulation (**NVIDIA only**, installed with `--quantum-gpu`) |

---

## Start the cluster

```bash
./setup/04-start-cluster.sh
```

The script runs pre-flight checks (pyenv, SPANK plugin, credentials) before starting the cluster and waits for `slurmctld` to become ready. It then prints the cluster node state and confirms the SPANK `--qpu` option is visible.

The cluster includes a `login` node (uses the control image) that provides a persistent entry point for interactive use.

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
# Basic verification — no GPU or credentials required
./setup/05-verify.sh

# Include GPU tests (requires g1 and/or qg1 with NVIDIA CUDA GPU)
./setup/05-verify.sh --gpu

# Include QRMI connectivity test (requires valid credentials and network access)
./setup/05-verify.sh --qrmi

# Full verification
./setup/05-verify.sh --gpu --qrmi
```

A passing run confirms: containers up, Slurm responding, SPANK plugin loaded, `/shared/pyenv` mounted and importable on all nodes, Qiskit Bell state circuit executes correctly, and batch job submission works end to end.

> **Note:** The `--qrmi` test submits a real Slurm job to the `quantum` partition using `--qpu`. It requires valid credentials in `/etc/slurm/qrmi_config.json` on both `slurmctld` and `q1`, and an IBM Quantum instance with available compute time. A successful connection but empty backend list typically indicates your instance quota is exhausted, not a configuration error.

---

## Updating packages

Because the quantum stack lives in `/shared/pyenv` on the host rather than baked into the images, you can update packages without rebuilding any images:

```bash
# Rebuild /shared/pyenv with updated packages (no GPU)
./setup/02-build-shared.sh --force

# Rebuild with CuPy (g1)
./setup/02-build-shared.sh --force --gpu

# Rebuild with qiskit-aer-gpu (qg1)
./setup/02-build-shared.sh --force --quantum-gpu

# Rebuild with both
./setup/02-build-shared.sh --force --gpu --quantum-gpu
```

To update only pip packages without rebuilding qrmi and the SPANK plugin (much faster):

```bash
./setup/02-build-shared.sh --packages-only
./setup/02-build-shared.sh --packages-only --gpu              # include CuPy
./setup/02-build-shared.sh --packages-only --quantum-gpu      # include qiskit-aer-gpu
./setup/02-build-shared.sh --packages-only --gpu --quantum-gpu
```

Then restart the cluster:

```bash
podman compose -f cluster/docker-compose.yml restart
```

To update pinned versions, edit `requirements/pyenv-frozen.txt` before running `--force`.

To regenerate the lockfile from the current environment:

```bash
podman exec c1 /shared/pyenv/bin/pip freeze | grep -v '^qrmi' > requirements/pyenv-frozen.txt
```

---

## Troubleshooting

**slurm.conf / gres.conf / docker-compose.yml are missing after clone**

These files are not committed to the repository — they are generated from templates by `00b-configure-system.sh`. If they are missing (e.g. after a fresh clone), run:

```bash
cp .env.example .env
./setup/00b-configure-system.sh
```

If you accidentally edited a generated file directly and want to reset it to the correct values for your hardware, simply re-run the script — it overwrites the generated files from the templates each time.

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
podman exec q1 bash -c "ls -lh /shared/spank-plugins/plugins/spank_qrmi/build/spank_qrmi.so"
podman exec q1 bash -c "cat /etc/slurm/plugstack.conf"
```

If the `.so` is missing, run `./setup/02-build-shared.sh --force`.

**qrmi import fails on q1**

```bash
podman exec q1 bash -c "source /shared/pyenv/bin/activate && python3 -c 'import qrmi'"
```

If you see a Rust/ABI error, the qrmi wheel was built against a different system ABI. Run `./setup/02-build-shared.sh --force` to rebuild the wheel inside the builder container.

**GPU not detected on g1 or qg1**

> This requires an NVIDIA GPU with CUDA. AMD and Intel GPUs are not supported.

```bash
# Test CuPy on g1
podman exec g1 bash -c "source /shared/pyenv/bin/activate && python3 -c 'import cupy; print(cupy.cuda.runtime.getDeviceCount())'"

# Test qiskit-aer-gpu on qg1
podman exec qg1 bash -c "source /shared/pyenv/bin/activate && python3 -c 'from qiskit_aer import AerSimulator; print(AerSimulator.from_backend.__doc__)'"
```

On WSL2, verify `/usr/lib/wsl/lib` is bind-mounted and `/dev/dxg` exists on the host. Also confirm that `nvidia.com/gpu=all` is listed under `devices` for both `g1` and `qg1` in `cluster/docker-compose.yml` and that CDI is configured at `/etc/cdi/nvidia.yaml` on the host.

If CuPy is not installed, run `./setup/02-build-shared.sh --gpu`. If qiskit-aer-gpu is not installed, run `./setup/02-build-shared.sh --quantum-gpu`.

**QRMI job connects but finds no backends**

This is expected if your IBM Quantum instance has 0 seconds of compute time remaining. The QRMI integration itself is working correctly — the quota is exhausted. Check your instance usage at https://quantum.cloud.ibm.com.

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
