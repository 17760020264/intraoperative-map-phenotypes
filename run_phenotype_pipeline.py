from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def run(arguments: list[str]) -> None:
    print("\n>", " ".join(arguments), flush=True)
    subprocess.run(arguments, cwd=ROOT, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create MAP descriptors and apply the submitted frozen MOVER phenotype model to two harmonized trajectory files."
    )
    parser.add_argument("--mover-map", required=True, help="Clinically eligible MOVER long-form MAP CSV")
    parser.add_argument("--inspire-map", required=True, help="Clinically eligible INSPIRE version 1.0 long-form MAP CSV")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--rederive-audit", action="store_true", help="Also refit a separate MOVER model for derivation reproducibility auditing")
    args = parser.parse_args()

    output = Path(args.output_dir).resolve()
    output.mkdir(parents=True, exist_ok=True)
    mover_descriptors = output / "MOVER_91_MAP_DESCRIPTORS.csv"
    inspire_descriptors = output / "INSPIRE_1_0_91_MAP_DESCRIPTORS.csv"

    for input_file, descriptor_file in (
        (args.mover_map, mover_descriptors),
        (args.inspire_map, inspire_descriptors),
    ):
        run([
            args.python,
            "pipeline/01_compute_map_descriptors.py",
            "--input", str(Path(input_file).resolve()),
            "--output", str(descriptor_file),
            "--min-or-duration", "60",
        ])

    for descriptor_file, assignment_file in (
        (mover_descriptors, output / "MOVER_FROZEN_PHENOTYPE_ASSIGNMENTS.csv"),
        (inspire_descriptors, output / "INSPIRE_1_0_FROZEN_PHENOTYPE_ASSIGNMENTS.csv"),
    ):
        run([
            args.python,
            "pipeline/03_apply_frozen_model.py",
            "--input", str(descriptor_file),
            "--output", str(assignment_file),
            "--model-dir", str(ROOT / "model"),
        ])

    if args.rederive_audit:
        run([
            args.python,
            "pipeline/02_fit_derivation_model.py",
            "--input", str(mover_descriptors),
            "--output-dir", str(output / "MOVER_REDERIVED_MODEL_AUDIT"),
        ])

    print("\nPhenotype workflow complete:", output)
    print("The submitted external-validation result is the INSPIRE assignment produced with model/; do not use the rederived audit model for INSPIRE.")


if __name__ == "__main__":
    main()
