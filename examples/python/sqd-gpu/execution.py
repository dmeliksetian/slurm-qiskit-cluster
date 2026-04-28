"""
execution.py — Step 3: Run ISA circuits on quantum hardware and save counts.
"""

from qiskit.primitives import BitArray
from qrmi.primitives.ibm import SamplerV2

from config import ISA_CIRCUITS_FILE, COUNTS_FILE, DEFAULT_SHOTS
from common import load_circuits, save_counts, get_qrmi_resource, get_logger

log = get_logger("execution")


if __name__ == "__main__":
    isa_circuits = load_circuits(ISA_CIRCUITS_FILE)
    log.info(f"Loaded {len(isa_circuits)} ISA circuits from {ISA_CIRCUITS_FILE}")

    qrmi = get_qrmi_resource()
    options = {"default_shots": DEFAULT_SHOTS}
    sampler = SamplerV2(qrmi, options=options)

    log.info(f"Submitting {len(isa_circuits)} circuits with {DEFAULT_SHOTS} shots each")
    job = sampler.run(isa_circuits)

    bit_array = BitArray.concatenate_shots(
        [result.data.meas for result in job.result()]
    )
    counts = bit_array.get_counts()

    save_counts(COUNTS_FILE, counts)
    log.info(f"Saved counts to {COUNTS_FILE}")
    log.info(f"Total bitstrings: {sum(counts.values())}")
