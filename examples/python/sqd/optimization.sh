#!/bin/bash
#SBATCH --job-name=sqd-optimization
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=normal
# Backend names differ by IBM Quantum instance and region: replace ibm_marrakesh with a name from your qrmi_config.json.
#SBATCH --qpu=ibm_marrakesh
#SBATCH --output=logs/%j-optimization.out
#SBATCH --error=logs/%j-optimization.err

cd "$SLURM_SUBMIT_DIR"
source /shared/pyenv/bin/activate

python -u /shared/examples/python/sqd/optimization.py
