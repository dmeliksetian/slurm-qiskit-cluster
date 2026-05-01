# QRMI Job

**Demonstrates:** Submitting a single quantum job to a real QPU via QRMI.

## What it does

Builds a random parameterised circuit (`pauli_two_design`) and an observable (`SparsePauliOp`), transpiles it to the target QPU, and runs it using `EstimatorV2` through the QRMI interface. Prints the job ID and resulting expectation value.

This is the minimal template for any QPU job on the cluster — acquire a QRMI resource, transpile, run, read results.

## Workflow

```
qrmi_job.sh
  └── srun python qrmi_job.py
        acquire QRMI resource → get target
        build + transpile circuit
        EstimatorV2.run() → print expectation value
```

## Files

| File | Description |
|------|-------------|
| `qrmi_job.py` | Circuit construction, transpilation, and QPU execution via QRMI |
| `qrmi_job.sh` | SLURM job: 1 task, `partition=quantum`, `--gres=qpu:1`, `--qpu=ibm_marrakesh` |

## Run

```bash
sbatch qrmi_job.sh
```
