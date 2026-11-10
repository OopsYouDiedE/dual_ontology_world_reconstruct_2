"""Verify and restore the versioned, compressed campaign model sources.

Only generated GLBs named by this manifest are managed. Authored scenes, DV,
fonts, character designs, and Blender sources are never overwritten here.
"""
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets/packs/campaign_assets.json"
PREFIXES = ("assets/scenes/campaign_rooms/models/", "assets/imported/kaykit/animations/")


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def ensure():
    if not MANIFEST.is_file():
        return {"available": False, "installed": 0}
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("schema") != "dowe-campaign-assets-v1":
        raise ValueError("Unknown campaign asset bundle schema")
    members = {}
    missing = []
    for item in manifest["files"]:
        name = item["path"]
        target = (ROOT / name).resolve()
        if not name.startswith(PREFIXES) or not name.endswith(".glb") or not target.is_relative_to(ROOT) or name in members:
            raise ValueError("Invalid campaign asset member: " + name)
        members[name] = item
        if not target.is_file() or target.stat().st_size != item["bytes"] or digest(target) != item["sha256"]:
            missing.append(name)
    if not missing:
        return {"available": True, "files": len(members), "installed": 0, "verified": True}
    cache = ROOT / ".runtime/asset-packages"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / (manifest["archive_sha256"] + ".zip")
    if not archive.is_file() or digest(archive) != manifest["archive_sha256"]:
        with tempfile.NamedTemporaryFile(dir=cache, suffix=".zip", delete=False) as output:
            pending = Path(output.name)
            for item in manifest["parts"]:
                part = (MANIFEST.parent / item["name"]).resolve()
                if part.parent != MANIFEST.parent or not part.is_file() or digest(part) != item["sha256"]:
                    raise ValueError("Missing or damaged versioned asset part: " + item["name"])
                output.write(part.read_bytes())
        if pending.stat().st_size != manifest["archive_bytes"] or digest(pending) != manifest["archive_sha256"]:
            raise ValueError("Campaign asset archive verification failed")
        pending.replace(archive)
    with zipfile.ZipFile(archive) as bundle:
        if len(bundle.namelist()) != len(members) or set(bundle.namelist()) != set(members):
            raise ValueError("Campaign archive members differ from its manifest")
        for name in missing:
            item = members[name]
            info = bundle.getinfo(name)
            if info.file_size != item["bytes"]:
                raise ValueError("Unexpected campaign asset length: " + name)
            content = bundle.read(name)
            if hashlib.sha256(content).hexdigest() != item["sha256"]:
                raise ValueError("Campaign asset verification failed: " + name)
            target = ROOT / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=target.parent, suffix=".tmp", delete=False) as output:
                pending = Path(output.name)
                output.write(content)
            pending.replace(target)
    return {"available": True, "files": len(members), "installed": len(missing), "verified": True}


if __name__ == "__main__":
    print(json.dumps(ensure(), ensure_ascii=False))
