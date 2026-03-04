# 1. Stop and remove all cluster containers and volumes
podman compose -f cluster/docker-compose.yml down -v

# 2. Remove all cluster images
podman rmi slurm-qiskit-builder:latest \
           slurm-qiskit-control:latest \
           slurm-qiskit-compute:latest \
           slurm-qiskit-quantum:latest \
           slurm-qiskit-gpu:latest \
           slurm-qiskit-quantum-gpu:latest \
           2>/dev/null || true

# 3. Wipe /shared/pyenv and build artifacts
rm -rf shared/pyenv
rm -f shared/spank-plugins/plugins/spank_qrmi/build/spank_qrmi.so

# 4. Full podman reset — removes ALL images, containers, volumes, networks
podman system reset --force