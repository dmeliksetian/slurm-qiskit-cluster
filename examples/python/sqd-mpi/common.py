"""
common.py — Shared utilities used across all workflow steps.

Provides:
  - Logging setup
  - File I/O helpers (QPY, JSON, generic)
  - QRMI resource acquisition (used by optimization and execution)
"""

import json
import logging
import sys
from pathlib import Path

from qiskit import qpy


# ── Logging ────────────────────────────────────────────────────────────────

def get_logger(name: str) -> logging.Logger:
    """Return a logger that writes timestamped messages to stdout."""
    logging.basicConfig(
        stream=sys.stdout,
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    return logging.getLogger(name)


# ── File I/O ───────────────────────────────────────────────────────────────

def _ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _check_exists(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(
            f"Expected input file not found: {path}\n"
            "Did a previous pipeline step fail or not run yet?"
        )


def save_circuits(path: Path, circuits) -> None:
    _ensure_parent(path)
    with open(path, "wb") as f:
        qpy.dump(circuits, f)


def load_circuits(path: Path):
    _check_exists(path)
    with open(path, "rb") as f:
        return qpy.load(f)


def save_counts(path: Path, counts: dict) -> None:
    _ensure_parent(path)
    with open(path, "w") as f:
        json.dump(counts, f)


def load_counts(path: Path) -> dict:
    _check_exists(path)
    with open(path, "r") as f:
        return json.load(f)


# ── QRMI resource acquisition ──────────────────────────────────────────────

def get_qrmi_resource():
    """
    Load environment, initialise QRMIService, and return the first
    available resource.  Raises if none are available.

    Used by optimization.py and execution.py — both need the same
    resource-acquisition pattern.
    """
    from dotenv import load_dotenv
    from qrmi.primitives import QRMIService

    load_dotenv()
    service = QRMIService()
    resources = service.resources()
    if not resources:
        raise ValueError("No quantum resource is available.")
    return resources[0]
