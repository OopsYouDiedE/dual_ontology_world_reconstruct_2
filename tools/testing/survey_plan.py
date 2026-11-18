"""Expand named story fixtures into self-contained development survey job plans."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path


def resolve_case(case, root):
    result = deepcopy(case)
    path = result.pop("scenario_path", None)
    if path is None:
        if not isinstance(result.get("fixture"), dict):
            raise ValueError("Survey case requires a named scenario or a legacy inline fixture")
        return result
    if "fixture" in result:
        raise ValueError("Choose a named scenario or a legacy inline fixture")
    scenarios = Path(root).resolve() / "assets/data/test_scenarios/segments"
    relative = Path(str(path).removeprefix("res://"))
    fixture_path = (Path(root).resolve() / relative).resolve()
    if fixture_path.parent != scenarios or fixture_path.suffix != ".json":
        raise ValueError("Survey scenario must name a project segment JSON file")
    raw = fixture_path.read_bytes()
    fixture = json.loads(raw.decode("utf-8-sig"))
    result["scenario_source"] = "res://" + fixture_path.relative_to(Path(root).resolve()).as_posix()
    result["scenario_sha256"] = hashlib.sha256(raw).hexdigest()
    if not isinstance(fixture, dict) or fixture.get("id") != result.get("id"):
        raise ValueError("Survey case ID must match the scenario ID")
    if result.get("snapshot"):
        # A recorded survey checkpoint supersedes the scenario's default one.
        fixture.pop("presentation_snapshot", None)
    overrides = result.pop("mock_overrides", {})
    if not isinstance(overrides, dict):
        raise ValueError("Survey mock_overrides must be a mapping")
    if overrides:
        fixture.setdefault("mock", {}).update(overrides)
    result["fixture"] = fixture
    return result
