# slurm-qiskit-cluster

A self-contained Slurm cluster for running quantum computing workloads locally using [Qiskit](https://github.com/Qiskit/qiskit) and [QRMI](https://github.com/qiskit-community/qrmi). Built with Podman and designed to run on any Linux host, including WSL2.

---

## What it does

Provides a multi-node Slurm cluster where quantum jobs are submitted through standard `sbatch` / `salloc` commands and routed to real quantum hardware (IBM Quantum, Pasqal) or GPU-accelerated simulation via a SPANK plugin. The full quantum Python stack is shared across all nodes via a bind-mounted virtual environment, so updating packages never requires rebuilding container images.

## Architecture

```
Host ./shared/
  ├── pyenv/            ← quantum Python stack (qiskit, qrmi, ffsim, pyscf ...)
  ├── qrmi/             ← git submodule: qiskit-community/qrmi
  └── spank-plugins/    ← git submodule: qiskit-community/spank-plugins
        └── plugins/spank_qrmi/build/spank_qrmi.so

Container stages:
  base
    ├── builder         ← ephemeral — populates ./shared once before cluster starts
    ├── control         ← slurmctld, slurmdbd (login node)
    └── compute-base    ← c1, c2 (general compute)
          ├── quantum   ← q1 (IBM Quantum / Pasqal via QRMI)
          └── gpu       ← g1 (GPU postprocessing — CuPy, Dice)
                └── quantum-gpu  ← qg1 (GPU-accelerated Aer simulation)
```

## Quantum workflow

```
c1 / c2   build and transpile circuits (Qiskit)
   ↓
q1        submit to real hardware via QRMI SPANK plugin
   ↓
g1        GPU postprocessing (SQD, Dice eigensolver, CuPy)
```

## Prerequisites

- Linux host (bare metal or WSL2) with Podman 4.0+
- `podman compose` (`dnf install podman-compose` or `pip install podman-compose`)
- Git with submodule support
- NVIDIA GPU + drivers (optional — required for g1 / qg1 only)
- IBM Quantum account for QRMI jobs (free tier supported for `qiskit-runtime-service` backends)

See [InstallationGuide.md](InstallationGuide.md) for platform-specific setup instructions.

## Quick start

```bash
# 1. Clone with submodules
git clone --recurse-submodules https://github.com/<you>/slurm-qiskit-cluster.git
cd slurm-qiskit-cluster

# 2. Configure
cp .env.example .env                        # set SLURM_TAG and versions
./setup/03-configure-credentials.sh        # set up qrmi_config.json

# 3. Build
./setup/00-check-prereqs.sh
./setup/01-build-images.sh
./setup/02-build-shared.sh                 # ~15 min — builds pyenv + SPANK plugin

# 4. Start
./setup/04-start-cluster.sh

# 5. Verify
./setup/05-verify.sh
```

Full details in [InstallationGuide.md](InstallationGuide.md).

## Repository structure

```
slurm-qiskit-cluster/
├── .env.example                 # copy to .env and configure
├── cluster/
│   ├── Dockerfile               # multi-stage image definition
│   ├── docker-compose.yml       # all services and volume mounts
│   ├── build-all.sh             # runs inside builder container
│   └── config/                  # Slurm config files
│       ├── slurm.conf
│       ├── plugstack.conf
│       ├── qrmi_config.json.example
│       └── ...
├── requirements/
│   └── pyenv-frozen.txt         # pinned pip lockfile (excludes qrmi)
├── shared/                      # bind-mounted into all containers
│   ├── qrmi/                    # submodule: qiskit-community/qrmi
│   └── spank-plugins/           # submodule: qiskit-community/spank-plugins
└── setup/
    ├── 00-check-prereqs.sh
    ├── 01-build-images.sh
    ├── 02-build-shared.sh
    ├── 03-configure-credentials.sh
    ├── 04-start-cluster.sh
    └── 05-verify.sh
```

## AI disclosure

This project was developed with the assistance of [Claude](https://claude.ai) (Anthropic). Claude was used to help design the repository structure, write the multi-stage Dockerfile, setup scripts, and documentation.

## Acknowledgements and sources

This project consolidates and extends the following upstream sources:

- **[christopherporter1/hpc-course-demos](https://github.com/christopherporter1/hpc-course-demos)** — original HPC + Quantum course materials, installation instructions, and the `q1_container.sh` script that this repo replaces with a reproducible build process.

- **[qiskit-community/spank-plugins — slurm-docker-cluster demo](https://github.com/qiskit-community/spank-plugins/tree/main/demo/qrmi/slurm-docker-cluster)** — the reference QRMI + SPANK plugin integration for Slurm, including the original installation instructions for building the plugin and configuring `plugstack.conf`.

- **[giovtorres/slurm-docker-cluster](https://github.com/giovtorres/slurm-docker-cluster)** — the upstream Slurm Docker cluster that provided the base `Dockerfile` and `docker-entrypoint.sh`.

- **[qiskit-community/qrmi](https://github.com/qiskit-community/qrmi)** — the Quantum Resource Management Interface Python package and Rust extension, included as a git submodule.

## License

Apache 2.0 — see [LICENSE](LICENSE).
