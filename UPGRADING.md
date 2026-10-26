<!--
Tested on one machine (NVIDIA Blackwell GPU, Linux, real IBM Quantum hardware) in an
isolated checkout: fresh v0.2.1 build, upgrade to v0.2.2, then the steps below with the
wip/stack-upgrade-2026-10 branch standing in for v0.3.0. Each stage passed
05-verify.sh --gpu --qrmi. That run rebuilt the images; the mounted lockfile and
build script (step 6 now skipped) were tested separately. Not yet tested: the whole
walkthrough without the image rebuild, the rollback section, and GPUs other
than Blackwell. Re-run once the v0.3.0 tag exists.
-->

# Upgrading

This guide covers upgrading an existing cluster from **v0.2.2 to v0.3.0**. Releases older than v0.2.2 are not covered; upgrade to v0.2.2 first. See the Versions table in [README.md](README.md) for what each release contains.

## What changes in v0.3.0

| | v0.2.2 | v0.3.0 |
|---|---|---|
| qiskit | 2.3.0 in the lockfile (a GPU build installs the newest, see note) | 2.6.1 |
| qiskit-aer | 0.17.x (GPU build from a patched fork) | 0.18.0 (GPU build from fork tag `v0.2.0`) |
| qiskit-ibm-runtime | 0.45.1 | 0.51.0 |
| qiskit-addon-sqd | 0.12.1 | 0.14.0 |
| qiskit_pasqal_provider / pulser | 0.1.1 / 1.6.6 | 0.5.0 / 1.9.1 |
| ffsim / pyscf | 0.0.67 / 2.12.1 | 0.0.85 / 2.14.0 |
| qrmi | v0.11.0 + 5 commits | 0.26.4 |
| spank-plugins | v0.4.0 + 14 commits | 0.12.0 |

The exact package pins are in `requirements/pyenv-frozen.txt`.

Note on v0.2.x: with `--quantum-gpu`, its build installed the Aer wheel with full dependency resolution, which replaced the lockfile's qiskit with the newest release (2.6.1 when this guide was tested). So a v0.2.x GPU cluster may already run a newer qiskit than the lockfile says. v0.3.0 installs the wheel with `--no-deps`, and the lockfile is respected.

**This upgrade recompiles the GPU qiskit-aer.** The node images are not rebuilt, but the shared environment is, and that includes compiling qiskit-aer 0.18.0 from source (the fork at tag `v0.2.0`) against your CUDA version, because no prebuilt GPU wheel exists for newer CUDA versions and GPU architectures. This is the longest step and cannot be skipped if you use the `qg1` node; it takes longer on machines with few CPUs or little memory (see `AER_JOBS` in step 4). A cluster without a GPU gets the CPU Aer from the lockfile instead and skips the compile.

**This is a breaking change for `qrmi_config.json`.** Upstream QRMI renamed two IBM resource types and their environment variable prefixes, and v0.3.0 uses the new names. A `qrmi_config.json` written for v0.2.x must be edited (step 3).

## Before you start

- Back up your local files that are not in git:
  ```bash
  cp cluster/config/qrmi_config.json ~/qrmi_config.json.v0.2.2
  cp .env ~/env.v0.2.2
  ```
- Plan for downtime and a long rebuild. The shared environment is rebuilt from scratch, and recompiling the GPU qiskit-aer takes the longest (step 7). The node images are not rebuilt (step 6).
- Your Slurm accounting database, munge keys and job data live in named volumes. They are kept.
- `/shared/pyenv` is replaced, not updated. Packages you installed into it by hand are lost.

## Steps

### 1. Stop the cluster

```bash
./setup/06-stop-cluster.sh
```

Do not use `--volumes`; that deletes the named volumes. The shared environment is deleted and rebuilt in step 7, so the cluster must not be running.

### 2. Get the new release

```bash
git fetch --tags
git checkout v0.3.0
git submodule update --init --recursive
git submodule status
```

The submodule status should show `shared/qrmi` at `0.26.4` and `shared/spank-plugins` at `0.12.0`, with no leading `+` or `-`.

### 3. Migrate `qrmi_config.json`

The renames:

| Resource type | v0.2.2 | v0.3.0 |
|---|---|---|
| IBM Quantum Platform | `qiskit-runtime-service` | `ibm-quantum-compute-service` |
| IBM Quantum System API | `direct-access` | `ibm-quantum-system` |

| Environment key prefix | v0.2.2 | v0.3.0 |
|---|---|---|
| IBM Quantum Platform | `QRMI_IBM_QRS_` | `QRMI_IBM_QCS_` |
| IBM Quantum System API | `QRMI_IBM_DA_` | `QRMI_IBM_QS_` |

The key names after the prefix (`ENDPOINT`, `IAM_APIKEY`, `SERVICE_CRN`, `SESSION_MODE`, and so on) are unchanged. The resource `name` values (for example `ibm_fez`) are not affected.

```bash
sed -i -e 's/qiskit-runtime-service/ibm-quantum-compute-service/g' \
       -e 's/QRMI_IBM_QRS_/QRMI_IBM_QCS_/g' \
       -e 's/"direct-access"/"ibm-quantum-system"/g' \
       -e 's/QRMI_IBM_DA_/QRMI_IBM_QS_/g' cluster/config/qrmi_config.json

python3 -c "import json; json.load(open('cluster/config/qrmi_config.json')); print('valid JSON')"
```

`cluster/config/qrmi_config.json.example` shows the new format. Do not skip this step: qrmi 0.26.4 accepts the old Quantum Platform names only until **November 21, 2026**, and it no longer accepts `direct-access` at all.

### 4. Update `.env`

Keep your existing `.env`. Add the new settings from `.env.example`:

```bash
AER_REPO=https://github.com/dmeliksetian/qiskit-aer.git
AER_REF=v0.2.0
AER_JOBS=
```

`AER_REPO` and `AER_REF` choose the qiskit-aer source for the GPU build (`--quantum-gpu`). The defaults are what v0.3.0 was tested with. `AER_JOBS` limits the parallel compile jobs; leave it empty to use all CPUs. If the machine has many CPUs but little memory, set it lower (for example `AER_JOBS=8`).

`CUDA_ARCH` must be set for the GPU build. If it is empty in your `.env`, step 5 fills it in.

### 5. Detect hardware (only if needed)

The Slurm configuration files and the compose file are unchanged between v0.2.2 and v0.3.0, so you do not need to regenerate them. Run this only if `CUDA_ARCH` is empty in `.env`, or the GPU or CUDA version on the host changed:

```bash
./setup/00b-configure-system.sh      # answer y at the prompt
```

The script asks "Generate config files with these values? [y/N]" and has no non-interactive option. Without a terminal it exits without writing anything.

### 6. Rebuild the node images (usually not needed)

**Skip this step for v0.2.2 → v0.3.0.** (This is separate from the qiskit-aer compile in step 7, which you cannot skip.) The node images are unchanged between these releases, and the lockfile and `cluster/build-all.sh` are mounted from your checkout when the shared environment is built (step 7), so a new release's pins and build script are used without rebuilding anything.

Rebuild only if `cluster/Dockerfile` changed in a release you are moving across, or you changed `CUDA_VERSION` in `.env`:

```bash
./setup/01-build-images.sh --quantum-gpu     # drop --quantum-gpu if you do not use qg1
```

The layer cache may miss for many stages, so this can take a long time.

### 7. Rebuild the shared environment

```bash
./setup/02-build-shared.sh --force --gpu --quantum-gpu
```

Use the flags that match your cluster (`--gpu` for g1, `--quantum-gpu` for qg1). Do not use `--packages-only`: it skips the lockfile, qrmi and the SPANK plugin, which all changed.

The script builds the pinned Python environment, the qiskit-aer GPU wheel (compiled from source with `--quantum-gpu`; this is the longest part), the qrmi 0.26.4 wheel and `spank_qrmi.so` from spank-plugins 0.12.0.

### 8. Start the cluster

```bash
./setup/04-start-cluster.sh
```

### 9. Copy the new config into the cluster

`/etc/slurm` is a named volume shared by all containers. It is filled from the image only when the volume is first created, so the rebuilt images do not update it. The containers were removed in step 1, so this step has to come after they are started. Copy the migrated file in once:

```bash
podman cp cluster/config/qrmi_config.json slurmctld:/etc/slurm/qrmi_config.json
```

No restart is needed; the SPANK plugin reads the file when a job starts. Check that a compute node sees it:
```bash
podman exec q1 grep -c ibm-quantum-compute-service /etc/slurm/qrmi_config.json
```

### 10. Verify

```bash
./setup/05-verify.sh --gpu --qrmi
```

Leave out `--gpu` or `--qrmi` if they do not apply to you. A passing run reports qiskit 2.6.1 on every node, and `qiskit-aer 0.18.0` on qg1.

The `--qrmi` check submits a real Bell-state job to IBM Quantum and uses your quota. It tries each configured QPU in turn:
- a QPU that is paused or not accessible gives a warning, and the next one is tried;
- the check passes as soon as one QPU runs the circuit;
- if a job hits the 30-minute Slurm limit (a long IBM queue) it gives a warning, not a failure;
- any other failure, such as bad credentials, stops the check.

Set `QRMI_TIMEOUT` (seconds, default 3600) to change how long the script waits for each job.

## Troubleshooting

**`04-start-cluster.sh` fails with `ModuleNotFoundError: No module named 'podman_compose'`**
The repository's `.venv` was built with a different Python than the one `python3` now points to. Repair it:
```bash
python3 -m venv --upgrade .venv
.venv/bin/pip install podman-compose==1.5.0
```

**`sbatch: error: ... spank_qrmi.so: undefined symbol` and `unrecognized option '--qpu'`**
The SPANK plugin was linked against an old qrmi library left over from a previous build. The build script of v0.3.0 and later always builds the plugin from a clean directory, and it is always taken from your checkout, so this should not happen after the steps above. Make sure you are on the v0.3.0 checkout, repeat step 7 and restart the cluster.

**A node shows as not responding after you restart a single container**
slurmctld can hold a stale address for it. Run `podman exec slurmctld scontrol reconfigure`. Restarting the whole cluster with `06-stop-cluster.sh` and `04-start-cluster.sh` avoids this.

**The qiskit-aer GPU build is killed or the machine freezes**
The compile starts one job per CPU, and each CUDA job can use several GB. Set `AER_JOBS` in `.env` to a lower number. On WSL2, you can also raise the memory limit; see the WSL2 section of [InstallationGuide.md](InstallationGuide.md).

**`qrmi_config.json` errors in a job**
A job that cannot acquire a QPU, or a missing-environment-variable error from qrmi, usually means a stanza still has an old type or prefix. Compare the file with `cluster/config/qrmi_config.json.example`. Also check that the node sees the new file (step 8), because the volume copy is separate from the one in the repository.

## Rolling back

Rebuilding is required in both directions, because the shared environment cannot hold two versions at once.

```bash
./setup/06-stop-cluster.sh
git checkout v0.2.2
git submodule update --init --recursive
cp ~/qrmi_config.json.v0.2.2 cluster/config/qrmi_config.json
cp ~/env.v0.2.2 .env
./setup/01-build-images.sh --quantum-gpu
./setup/02-build-shared.sh --force --gpu --quantum-gpu
./setup/04-start-cluster.sh
podman cp cluster/config/qrmi_config.json slurmctld:/etc/slurm/qrmi_config.json
```

The images are rebuilt in the rollback because v0.2.2's setup scripts expect the lockfile and build script inside the builder image, which images built from v0.3.0 no longer contain. The rollback sequence has not been tested.

The old qrmi (v0.11) does not understand the new resource names, so the config backup from "Before you start" must be restored.
