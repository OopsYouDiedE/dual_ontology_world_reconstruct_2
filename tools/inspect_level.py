#!/usr/bin/env python3
"""Single-command level diagnostic inspector for The Sleeping Academy.

Usage:
  python3 tools/inspect_level.py                  # Inspect default main scene (Public Hall)
  python3 tools/inspect_level.py --scene r01      # Inspect Chapter 1 R-01 (AcademyLevelBase)
  python3 tools/inspect_level.py --scene expedition # Inspect Expedition-01 North Wing
  python3 tools/inspect_level.py --json           # Print raw JSON payload
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def find_godot() -> str:
    for cand in [
        os.environ.get("GODOT_BIN", ""),
        shutil.which("godot") or "",
        shutil.which("godot4") or "",
        "/home/spark/godot_472/Godot_v4.7.2-stable_mono_linux_x86_64/Godot_v4.7.2-stable_mono_linux.x86_64",
        "/home/spark/godot/Godot_v4.7.2-stable_mono_linux_x86_64/Godot_v4.7.2-stable_mono_linux.x86_64",
    ]:
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    raise SystemExit("ERROR: Godot 4.7.2 binary not found. Set GODOT_BIN.")


def check_dependency_uniqueness() -> dict:
    formal_dirs = [
        "scenes/components", "scenes/rogue", "scenes/rogue_crossing",
        "scenes/rogue_view", "scenes/rogue_rules", "scenes/rogue_camp",
        "scenes/rogue_player", "scenes/expedition_01", "scenes/levels",
    ]
    blue_refs = []
    shared_exp_refs = []
    for d in formal_dirs:
        p = ROOT / d
        if not p.exists():
            continue
        for f in p.rglob("*"):
            if f.suffix not in (".gd", ".tscn", ".gdshader", ".cs"):
                continue
            txt = f.read_text(encoding="utf-8", errors="ignore")
            if "scenes/blue_prince_lab" in txt:
                blue_refs.append(str(f.relative_to(ROOT)))
            if d == "scenes/components" and "scenes/expedition_01" in txt:
                shared_exp_refs.append(str(f.relative_to(ROOT)))
    return {
        "ok": len(blue_refs) == 0 and len(shared_exp_refs) == 0,
        "formal_refs_to_blue_prince_lab": blue_refs,
        "shared_refs_to_expedition_01": shared_exp_refs,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Inspect loaded level, door topology, objects & interactables.")
    ap.add_argument("--scene", choices=["hall", "r01", "expedition"], default="hall")
    ap.add_argument("--json", action="store_true", dest="as_json")
    args = ap.parse_args()

    godot = find_godot()
    env = os.environ.copy()
    if Path("/home/spark/.dotnet/dotnet").exists():
        env["DOTNET_ROOT"] = "/home/spark/.dotnet"
        env["PATH"] = "/home/spark/.dotnet:" + env.get("PATH", "")

    cmd = [
        godot, "--headless", "--path", str(ROOT), "--audio-driver", "Dummy",
        "-s", "res://tools/test/level_debug_dump.gd", "--",
        "--no-rule-save", "--skip-intro", f"--scene={args.scene}",
    ]
    proc = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=60)
    out = proc.stdout + "\n" + proc.stderr
    m = re.search(r"===LEVEL_DEBUG_JSON_START===\s*(\{.*?\})\s*===LEVEL_DEBUG_JSON_END===", out, re.S)
    if not m:
        print(out[-2000:], file=sys.stderr)
        raise SystemExit(f"ERROR: Failed to parse level debug dump (exit={proc.returncode})")

    data = json.loads(m.group(1))
    data["dependency_gate"] = check_dependency_uniqueness()

    if args.as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return

    lvl = data["loaded_level"]
    dep = data["dependency_gate"]
    topo = data["door_topology"]
    print("=" * 72)
    print(f"当前加载关卡 : {lvl.get('title')}  [{lvl.get('level_id')}]")
    print(f"主场景入口   : {data.get('main_scene_config')}")
    print(f"运行管线     : {lvl.get('pipeline')}  |  当前交互样式: {lvl.get('ui_mode')}")
    caps = lvl.get("capabilities", {})
    print(f"能力开关     : jump={caps.get('allow_jump')}  lamp={caps.get('allow_lamp')}  stomp={caps.get('allow_stomp')}  wheel={caps.get('allow_command_wheel')}")
    print(f"依赖唯一门禁 : {'PASS (0 反向依赖)' if dep['ok'] else 'FAIL ' + str(dep)}")
    print("-" * 72)
    print("门拓扑逻辑 (Door & Route Topology):")
    if "active_exits" in topo:
        print(f"  当前房间: {topo.get('current_room')} | 已通关房间: {topo.get('cleared')}")
        for ex in topo.get("active_exits", []):
            print(f"  • 出口 #{ex['index']}: {ex['label']}  @{ex['pos']}  [已放行={ex['released']}]")
        graph = topo.get("house_graph", {})
        if graph:
            print("  全局房牌连线:")
            for k, v in graph.items():
                if v:
                    print(f"    {k} -> {', '.join(v)}")
    else:
        for k, v in topo.items():
            if k == "triggers":
                print(f"  触发器数: {len(v)}")
            else:
                print(f"  • {k}: {v}")
    print("-" * 72)
    print(f"房间内物体摘要 ({len(data['room_objects'])} 项):")
    for o in data["room_objects"]:
        print(f"  • {o.get('id')}  {o.get('pos', o.get('count', ''))}")
    print("-" * 72)
    print(f"可交互候选项 ({len(data['interactable_candidates'])} 组):")
    for g in data["interactable_candidates"]:
        print(f"  [{g['group_id']}] {g['title']}  @anchor={g['anchor_world']}")
        for h in g["hotspots"]:
            print(f"     └─ ({h['state']}) {h['part_name']} -> [E] {h['verb']}  @{h['world_pos']}  (解锁:{h['unlock_when']})")
    if data["ai_routes"]:
        print("-" * 72)
        print(f"AI 动作路线 ({len(data['ai_routes'])} 条):")
        for r in data["ai_routes"]:
            print(f"  • {r.get('actor_name')} ({len(r.get('waypoints', []))} 个路径点)")
    print("=" * 72)


if __name__ == "__main__":
    main()
