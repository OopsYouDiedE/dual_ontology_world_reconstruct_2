"""Validate a PNG source before using it as a scene reference or evidence."""
import argparse
import json
from pathlib import Path
import sys

from capture_provenance import verify_image


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image")
    parser.add_argument("--allow-fixture", action="store_true")
    arguments = parser.parse_args()
    try:
        result = verify_image(arguments.image, Path(__file__).resolve().parents[1], allow_fixture=arguments.allow_fixture)
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print(json.dumps({"provenance_valid": False, "error": str(error)}, ensure_ascii=False))
        sys.exit(1)
    print(json.dumps(result, ensure_ascii=False, indent=2))
