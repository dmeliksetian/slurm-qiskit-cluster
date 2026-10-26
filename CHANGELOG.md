# Changelog

All notable changes to this project are listed here, newest first. Versions are git tags (`vX.Y.Z`); see the Versions table in [README.md](README.md) for what each release contains. To move an existing cluster to a new release, follow [UPGRADING.md](UPGRADING.md).

## [0.3.0] - 2026-10-26

### Upgrade notes (read before upgrading from 0.2.x)

- **`qrmi_config.json` must be edited.** Upstream QRMI renamed two IBM resource types and their environment variable prefixes:

  | | 0.2.x | 0.3.0 |
  |---|---|---|
  | IBM Quantum Platform | `qiskit-runtime-service`, `QRMI_IBM_QRS_*` | `ibm-quantum-compute-service`, `QRMI_IBM_QCS_*` |
  | IBM Quantum System API | `direct-access`, `QRMI_IBM_DA_*` | `ibm-quantum-system`, `QRMI_IBM_QS_*` |

  qrmi 0.26.4 still accepts the old Quantum Platform names until **2026-11-21**. It no longer accepts `direct-access` at all.
- **The GPU qiskit-aer is recompiled.** The shared environment (`/shared/pyenv`) is rebuilt, and with `--quantum-gpu` that includes compiling qiskit-aer 0.18.0 from source. The node images are not rebuilt.
- The Slurm configuration files and the compose file are unchanged, so no regeneration is needed.

Step by step: [UPGRADING.md](UPGRADING.md).

### Changed

- **Python stack** (`requirements/pyenv-frozen.txt`): qiskit 2.3.0 → 2.6.1, qiskit-ibm-runtime 0.45.1 → 0.51.0, qiskit-addon-sqd 0.12.1 → 0.14.0, qiskit_pasqal_provider 0.1.1 → 0.5.0, ffsim 0.0.67 → 0.0.85, pyscf 2.12.1 → 2.14.0, pulser 1.6.6 → 1.9.1 (`pulser-pasqal` is no longer pulled in), pasqal-cloud 0.12.7 → 0.24.0, pydantic 2.12.5 → 2.13.5.
- **qrmi** v0.11.0 (+5 commits) → 0.26.4 and **spank-plugins** v0.4.0 (+14 commits) → 0.12.0. These are the first releases with the new IBM resource names.
- **qiskit-aer GPU build** (`--quantum-gpu`):
  - built from `AER_REPO` at the tag `AER_REF` (default: the fork's `v0.2.0`, based on qiskit-aer 0.18.0) instead of a moving branch;
  - its build dependencies (conan, scikit-build, cmake, ninja, pybind11) are installed in a throwaway virtual environment, not into `/shared/pyenv`;
  - the cuQuantum and cuTENSOR include paths are passed to the compiler;
  - `AER_JOBS` limits the number of parallel compile jobs.
- **Wheel installs use `--force-reinstall --no-deps`** for qiskit-aer and qrmi, so the lockfile is honoured. A 0.2.x GPU build replaced the lockfile's qiskit with the newest release.
- **The builder container takes the lockfile and `cluster/build-all.sh` from your checkout** (mounted read-only) instead of baked-in copies. Editing a pin or the build script takes effect on the next `02-build-shared.sh` without rebuilding images.
- qrmi's `requirements-dev.txt` (lint and test tooling) is no longer installed into the shared environment.
- **`05-verify.sh`**: the QRMI check tries each configured QPU in turn and reports a paused or inaccessible one as a warning; the job gets a 30-minute Slurm limit; a job that hits it is a warning; `QRMI_TIMEOUT` sets how long the script waits.
- **Examples**: `get_backend(...).target` instead of the deprecated `get_target` (qrmi 0.26.3); the READMEs now say to replace the hard-coded `--qpu` name with a resource from your own configuration, and that the `qaoa` example must be started from a compute node.
- **Documentation**: the Installation Guide (CUDA, CuPy and Aer descriptions, WSL2 steps, updating packages), the Versions table in the README.

### Added

- [UPGRADING.md](UPGRADING.md) and this changelog.
- `AER_REPO`, `AER_REF` and `AER_JOBS` in `.env.example`.
- Installation Guide: updating a few packages in seconds without any rebuild (`utilities/install-packages.sh`); the WSL2 CDI manifest step; notes on the CUDA version coming from the Windows driver and on limiting memory for the Aer build.
- `05-verify.sh` explains why the GPU checks fail when the shared environment has no GPU packages (`--gpu` and `--quantum-gpu` were not passed to `02-build-shared.sh`).

### Fixed

- **The SPANK plugin was linked against an old qrmi library after an upgrade** (`undefined symbol: EVP_bf_ecb`, `--qpu` missing from `sbatch`), because a leftover CMake build directory made the build skip `libqrmi.a`. The plugin is now always built from a clean directory.
- **CUDA detection with newer `nvidia-smi`** versions that print `CUDA UMD Version` instead of `CUDA Version`: `00b-configure-system.sh` left `CUDA_VERSION` at the example default and `00-check-prereqs.sh` printed no CUDA line.
- `05-verify.sh`: an unescaped `$2` in the `qg1` version lookup aborted the script (or printed a wrong version); a failed `sbatch` ended it silently.
- The Installation Guide described `--packages-only` as updating pip packages; it skips the lockfile.
- `00-check-prereqs.sh` pointed to a documentation file that does not exist.

### Notes

- **GPU libraries are resolved at build time and are deliberately not pinned.** CuPy, cuQuantum, cuTENSOR and the CUDA libraries are chosen from the CUDA version and GPU architecture that `00b-configure-system.sh` detects on the host, so two builds can differ in those packages.
- **Tested on** an NVIDIA RTX PRO 4500 Blackwell (CUDA 13.2, Linux), including the upgrade path v0.2.1 → v0.2.2 → v0.3.0, and on an RTX 2080 Ti under WSL2 (CUDA 13.4), including a fresh install. The final bump to qiskit 2.6.1, qiskit-ibm-runtime 0.51.0 and ffsim 0.0.85 was verified without a live QPU job, because of IBM queue lengths: job submission and result decoding were checked separately, qrmi's Python unit tests pass, and `05-verify.sh --qrmi` with a real IBM Quantum job passed on the preceding versions (qiskit 2.6.0, qiskit-ibm-runtime 0.50.0, ffsim 0.0.84).
- The upgrade from a clean v0.2.2 install to the v0.3.0 tag, without rebuilding the images, was tested on the Blackwell machine. The rollback section of [UPGRADING.md](UPGRADING.md) has not been tested.

## [0.2.2] - 2026-10-23

### Fixed

- Compute containers run with an init process (`init: true`), so defunct processes are reaped.
- JSON syntax errors in `cluster/config/qrmi_config.json.example`.

### Added

- `setup/06-stop-cluster.sh` for a clean teardown of the cluster.
- A Versions table in the README, release-aware checkout instructions, and a note on upgrading the qrmi and spank-plugins submodules.

## [0.2.1] - 2026-05-01

### Added

- GPU and QPU TRES accounting and time limits for the quantum partition, so that example jobs can report their resource use.

## [0.2.0] - 2026-04-28

### Added

- GPU build of qiskit-aer from source, for newer CUDA versions and GPU architectures such as Blackwell (`02-build-shared.sh --quantum-gpu`).

Earlier history: `git log v0.2.0`.

[0.3.0]: https://github.com/dmeliksetian/slurm-qiskit-cluster/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/dmeliksetian/slurm-qiskit-cluster/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/dmeliksetian/slurm-qiskit-cluster/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/dmeliksetian/slurm-qiskit-cluster/releases/tag/v0.2.0
