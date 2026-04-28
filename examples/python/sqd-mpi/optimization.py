"""
optimization.py — Step 2: Transpile circuits to ISA and save them.
"""

from qiskit.transpiler.preset_passmanagers import generate_preset_pass_manager
from qrmi.primitives.ibm import get_backend

from config import CIRCUITS_FILE, ISA_CIRCUITS_FILE, OPTIMIZATION_LEVEL
from common import load_circuits, save_circuits, get_qrmi_resource, get_logger

log = get_logger("optimization")


if __name__ == "__main__":
    log.info("Starting optimization step")

    circuits = load_circuits(CIRCUITS_FILE)
    log.info(f"Loaded {len(circuits)} circuits from {CIRCUITS_FILE}")

    log.info("Acquiring QRMI resource...")
    qrmi = get_qrmi_resource()
    log.info(f"QRMI resource acquired: {qrmi}")

    log.info("Getting backend...")
    backend = get_backend(qrmi)
    log.info(f"Backend: {backend.name}")

    log.info(f"Generating pass manager (optimization_level={OPTIMIZATION_LEVEL})...")
    pass_manager = generate_preset_pass_manager(
        optimization_level=OPTIMIZATION_LEVEL,
        backend=backend,
    )

    log.info(f"Transpiling {len(circuits)} circuits...")
    isa_circuits = pass_manager.run(circuits)

    save_circuits(ISA_CIRCUITS_FILE, isa_circuits)
    log.info(f"Saved {len(isa_circuits)} ISA circuits to {ISA_CIRCUITS_FILE}")
    print(isa_circuits[0].draw(scale=0.4))
