# slurm-qiskit-cluster — Cheat Sheet

## 1. Before you start

**Nuclear cleanup** (removes all podman containers, images, volumes):
```bash
podman system prune -af --volumes
```
Note: this does NOT remove host bind-mounts. Also clear `/shared/pyenv` manually if rebuilding:
```bash
rm -rf shared/pyenv
```

**WSL2 line endings** (if git complains on Windows):
```bash
git config core.autocrlf input
git checkout -- .gitignore
```

**Clone and check out a release:**
```bash
git clone https://github.com/dmeliksetian/slurm-qiskit-cluster.git
cd slurm-qiskit-cluster
git checkout v0.2.0
git submodule update --init --recursive
```

**Or update an existing clone to a new release:**
```bash
git fetch --tags
git checkout v0.2.0
git submodule update --init --recursive
```

---

## 2. Use-case guide

### A. Fresh install — with GPU
```bash
./setup/00-check-prereqs.sh
./setup/00b-configure-system.sh                        # detects CUDA version + compute arch, writes .env
./setup/01-build-images.sh --quantum-gpu               # all images + builder-gpu (needed for qg1 source build)
./setup/02-build-shared.sh --force --quantum-gpu --gpu # full pyenv + GPU qiskit-aer + cupy
./setup/03-configure-credentials.sh
./setup/04-start-cluster.sh
./setup/05-verify.sh --gpu --qrmi
```

### B. Fresh install — no GPU
```bash
./setup/00-check-prereqs.sh
./setup/00b-configure-system.sh
./setup/01-build-images.sh
./setup/02-build-shared.sh --force
./setup/03-configure-credentials.sh
./setup/04-start-cluster.sh
./setup/05-verify.sh --qrmi
```

### C. Upgrade existing cluster — with GPU
```bash
git fetch --tags
git checkout v0.2.0
git submodule update --init --recursive
./setup/00b-configure-system.sh           # if CUDA_VERSION/CUDA_ARCH not yet in .env
./setup/01-build-images.sh --quantum-gpu
./setup/02-build-shared.sh --quantum-gpu --gpu --packages-only  # adds GPU packages only, no full rebuild
podman restart g1 qg1
./setup/05-verify.sh --gpu --qrmi
```

### D. Upgrade existing cluster — no GPU
```bash
git fetch --tags
git checkout v0.2.0
git submodule update --init --recursive
./setup/05-verify.sh --qrmi               # nothing to rebuild
```

### E. Existing cluster (no GPU) — adding a GPU later
```bash
# After installing/connecting the GPU:
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml   # WSL2 only
./setup/00b-configure-system.sh           # detects new GPU, updates .env + docker-compose.yml
./setup/01-build-images.sh --quantum-gpu
./setup/02-build-shared.sh --quantum-gpu --gpu --packages-only
podman compose -f cluster/docker-compose.yml down
./setup/04-start-cluster.sh
./setup/05-verify.sh --gpu --qrmi
```

---

## 3. Maintenance

### Update credentials (API key change or new QPUs added)
Edit `cluster/config/qrmi_config.json` on the host, then:
```bash
podman cp cluster/config/qrmi_config.json slurmctld:/etc/slurm/qrmi_config.json
```
All nodes share the same `etc_slurm` volume — one copy updates everything. No restart needed.

### Install or upgrade specific packages without full rebuild
```bash
./utilities/install-packages.sh cupy-cuda12x           # example: add or upgrade a package
./utilities/install-packages.sh --from-file requirements/gpu-extras.txt
```
Skips pyenv-frozen.txt and qrmi/SPANK rebuild. Running containers pick up changes immediately.
If replacing qiskit-aer (CPU→GPU), restart affected nodes after:
```bash
podman restart g1 qg1
```

---

## 4. Troubleshooting

### GPU containers (g1, qg1) fail to start with "cannot stat /usr/lib/wsl/drivers/..."
The CDI spec is stale — Windows updated the NVIDIA driver and the hash changed. Regenerate:
```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```
Happens silently on any NVIDIA driver update. CDI spec lives outside the repo and survives `podman system prune`.

### Stop cluster without losing data
```bash
podman compose -f cluster/docker-compose.yml stop   # stops containers, keeps volumes
```

### Shut down WSL (after stopping cluster)
```bash
exit   # from WSL terminal
# then in PowerShell/CMD:
wsl --shutdown
```
