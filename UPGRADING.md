<!--
DRAFT. Written from the v0.3.0 development branch and a full rebuild on top of an
existing v0.2.x install. It has not yet been walked through from a clean v0.2.2
install. Remove this comment once it has.
-->

# Upgrading

This guide covers upgrading an existing cluster from **v0.2.2 to v0.3.0**. Releases older than v0.2.2 are not covered; upgrade to v0.2.2 first. See the Versions table in [README.md](README.md) for what each release contains.

## What changes in v0.3.0

| | v0.2.2 | v0.3.0 |
|---|---|---|
| qiskit | 2.3.0 | 2.6.0 |
| qiskit-aer | 0.17.1 (GPU build from a patched fork) | 0.18.0 (GPU build from fork tag `v0.2.0`) |
| qiskit-ibm-runtime | 0.45.1 | 0.50.0 |
| qiskit-addon-sqd | 0.12.1 | 0.14.0 |
| qiskit_pasqal_provider / pulser | 0.1.1 / 1.6.6 | 0.5.0 / 1.9.1 |
| ffsim / pyscf | 0.0.67 / 2.12.1 | 0.0.84 / 2.14.0 |
| qrmi | v0.11.0 + 5 commits | 0.26.4 |
| spank-plugins | v0.4.0 + 14 commits | 0.12.0 |

The exact package pins are in `requirements/pyenv-frozen.txt`.

**This is a breaking change for `qrmi_config.json`.** Upstream QRMI renamed two IBM resource types and their environment variable prefixes, and v0.3.0 uses the new names. A `qrmi_config.json` written for v0.2.x must be edited (step 3).

## Before you start

- Back up your local files that are not in git:
  ```bash
  cp cluster/config/qrmi_config.json ~/qrmi_config.json.v0.2.2
  cp .env ~/env.v0.2.2
  ```
- Plan for downtime and a long rebuild. The images and the shared environment are rebuilt from scratch, and building the GPU qiskit-aer from source takes the longest.
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

### 6. Rebuild the images

```bash
./setup/01-build-images.sh --quantum-gpu     # drop --quantum-gpu if you do not use qg1
```

The layer cache may miss for many stages, so this can take a long time. The builder image contains a copy of `cluster/build-all.sh`, so the images must be rebuilt for the build changes to take effect.

### 7. Rebuild the shared environment

```bash
./setup/02-build-shared.sh --force --gpu --quantum-gpu
```

Use the flags that match your cluster (`--gpu` for g1, `--quantum-gpu` for qg1). Do not use `--packages-only`: it skips the lockfile, qrmi and the SPANK plugin, which all changed.

The script builds the pinned Python environment, the qiskit-aer GPU wheel, the qrmi 0.26.4 wheel and `spank_qrmi.so` from spank-plugins 0.12.0.

### 8. Copy the new config into the cluster

`/etc/slurm` is a named volume shared by all containers. It is filled from the image only when the volume is first created, so a new image does not update it. Copy the migrated file in once:

```bash
podman cp cluster/config/qrmi_config.json slurmctld:/etc/slurm/qrmi_config.json
```

Check that a compute node sees it:
```bash
podman exec q1 grep -c ibm-quantum-compute-service /etc/slurm/qrmi_config.json
```

### 9. Start and verify

```bash
./setup/04-start-cluster.sh
./setup/05-verify.sh --gpu --qrmi
```

Leave out `--gpu` or `--qrmi` if they do not apply to you. A passing run reports qiskit 2.6.0 on every node.

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
podman cp cluster/config/qrmi_config.json slurmctld:/etc/slurm/qrmi_config.json
./setup/04-start-cluster.sh
```

The old qrmi (v0.11) does not understand the new resource names, so the config backup from "Before you start" must be restored.
