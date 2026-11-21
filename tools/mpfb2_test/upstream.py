"""Run upstream MPFB tests with Blender's Python; the source extension must be enabled."""
import argparse
from pathlib import Path
import sys

from bl_ext.user_default.mpfb.services.locationservice import LocationService


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pydeps", type=Path, required=True)
    parser.add_argument("--xml", type=Path, required=True)
    parser.add_argument("--test", default="tests", help="Path below MPFB's test directory")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert LocationService.is_source_dist(), "Enable MPFB from its src/mpfb checkout"
    base = Path(LocationService.get_mpfb_test()).resolve()
    tests = (base / args.test).resolve()
    assert tests.is_relative_to(base) and tests.exists(), tests
    sys.path.insert(0, str(args.pydeps.resolve()))
    import pytest
    status = pytest.main(["-q", "-ra", "--disable-warnings", "--junitxml", str(args.xml.resolve()), str(tests)])
    if status:
        raise RuntimeError(f"pytest suite finished with exit code {status}")


if __name__ == "__main__":
    main()
