"""Prepare, build, and open the production five-day Godot game."""
import argparse
import asyncio
import sys

from environment import resolve_godot
from run_environment import main as prepare_environment
from runtime import ROOT, build, spawn, terminate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ai", action="store_true", help="Start new games with the detective controlled by AI")
    parser.add_argument("--editor", action="store_true", help="Open the prepared project in Godot .NET")
    parser.add_argument("--with-blender", action="store_true", help="Also install or verify the local Blender dependency")
    options = parser.parse_args()
    asyncio.run(prepare_environment(local_copy=True, with_blender=options.with_blender))
    build("godot")
    command = [resolve_godot(), "--path", ROOT]
    if options.editor:
        command.append("--editor")
    else:
        command += ["--", "--dv-content=" + str(ROOT / "assets/data/scenarios/campaign.dv"),
                    "--dv-controller=" + ("ai" if options.ai else "player")]
    process = spawn(command)
    try:
        return process.wait()
    except KeyboardInterrupt:
        terminate(process)
        return 130


if __name__ == "__main__":
    sys.exit(main())
