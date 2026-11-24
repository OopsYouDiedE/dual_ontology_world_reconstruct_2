#!/usr/bin/env python3
"""Unified Level Graph Schema & Programmatic Iterative Level Optimizer.

Models Expedition-01 and Rogue-wing layouts in one canonical graph schema
(nodes = rooms/beats, edges = traversable links with physical distance,
resource deltas, and active rule contracts), then runs deterministic
multi-objective evaluation and iterative mutation search to propose and rank
structural improvements before building 3D geometry in Godot.

Usage:
    python3 tools/expedition/level_iterate.py [--json out.json]
"""

from __future__ import annotations

import argparse
import copy
import json
import math
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Set, Tuple


@dataclass
class RoomNode:
    id: str
    section: str  # A | B | C | RETURN
    role: str     # entry | hub | puzzle | resource | control | objective | exit | bypass
    rules: List[str] = field(default_factory=list)
    oil_delta: float = 0.0
    decision_points: int = 0
    is_checkpoint: bool = False


@dataclass
class RouteEdge:
    src: str
    dst: str
    length_m: float
    bidirectional: bool = True
    stance_req: str = "any"       # any | quiet | still | sprint
    oil_cost: float = 0.0
    noise_risk: float = 0.0       # 0..1
    rules_tested: List[str] = field(default_factory=list)
    tags: List[str] = field(default_factory=list)


@dataclass
class LevelGraph:
    name: str
    start: str
    objective: str
    exit_node: str
    nodes: Dict[str, RoomNode]
    edges: List[RouteEdge]


def build_expedition_01_baseline() -> LevelGraph:
    """Current Expedition-01 topology (A1/A2 -> B1..B5 -> C1 -> C5 -> Anchor)."""
    nodes = {
        "A1_arcade": RoomNode("A1_arcade", "A", "entry", ["B_iron_teach"], 0.0, 2),
        "A1_maint": RoomNode("A1_maint", "A", "resource", ["B_quiet"], 12.0, 2),
        "A2_niche": RoomNode("A2_niche", "A", "bypass", ["B_still_oil"], 24.0, 2),
        "B1_vestibule": RoomNode("B1_vestibule", "B", "hub", [], 0.0, 1),
        "B2_window": RoomNode("B2_window", "B", "puzzle", ["A_dual_gaze"], 0.0, 2),
        "B3_trial": RoomNode("B3_trial", "B", "puzzle", ["A_solo_lock", "A_handoff"], 0.0, 3),
        "B4_dark": RoomNode("B4_dark", "B", "resource", ["oil_drain"], 35.0, 1),
        "B4_loft": RoomNode("B4_loft", "B", "resource", ["felt_signal"], 0.0, 2),
        "B5_control": RoomNode("B5_control", "B", "control", ["A_gaze_persist"], 0.0, 2, is_checkpoint=True),
        "C1_mouth": RoomNode("C1_mouth", "C", "hub", ["A_gaze", "B_iron", "unison", "single_lamp"], 0.0, 3),
        "C1_core": RoomNode("C1_core", "C", "objective", ["A_gaze", "B_iron", "alarm"], 0.0, 1),
        "C1_floor": RoomNode("C1_floor", "C", "bypass", ["B_iron", "recovery"], 0.0, 1),
        "C5_gallery": RoomNode("C5_gallery", "RETURN", "exit", ["chase_fade"], 0.0, 1),
        "A0_anchor": RoomNode("A0_anchor", "RETURN", "exit", ["solo_or_duo_exit"], 0.0, 2),
    }
    edges = [
        RouteEdge("A1_arcade", "A1_maint", 27.2, True, "any", 0.0, 0.1, [], ["loop", "optional"]),
        RouteEdge("A1_arcade", "A2_niche", 14.0, True, "still", 0.0, 0.05, ["B_still_oil"], ["shortcut", "optional"]),
        RouteEdge("A2_niche", "B2_window", 11.5, True, "quiet", 0.0, 0.05, ["B_quiet"], ["shortcut"]),
        RouteEdge("A1_arcade", "B1_vestibule", 31.0, True, "any", 0.0, 0.1, [], ["main"]),
        RouteEdge("B1_vestibule", "B2_window", 8.0, True, "any", 0.0, 0.1, ["A_dual_gaze"], ["main"]),
        RouteEdge("B2_window", "B3_trial", 6.5, True, "any", 0.0, 0.1, ["A_solo_lock", "A_handoff"], ["main"]),
        RouteEdge("B3_trial", "B4_dark", 14.0, True, "any", 6.0, 0.15, ["oil_drain"], ["branch"]),
        RouteEdge("B4_dark", "B4_loft", 10.0, True, "quiet", 2.0, 0.05, ["felt_signal"], ["optional"]),
        RouteEdge("B4_dark", "B5_control", 9.0, True, "any", 3.0, 0.1, [], ["branch"]),
        RouteEdge("B3_trial", "B5_control", 13.5, True, "any", 0.0, 0.1, [], ["main"]),
        RouteEdge("B5_control", "C1_mouth", 11.0, True, "quiet", 0.0, 0.3, ["B_iron", "single_lamp"], ["main"]),
        RouteEdge("C1_mouth", "C1_core", 18.5, True, "quiet", 0.0, 0.75, ["A_gaze", "B_iron", "unison", "single_lamp"], ["main_bridge"]),
        RouteEdge("C1_mouth", "C1_core", 28.0, True, "any", 18.0, 0.35, ["B_iron", "oil_drain", "oil_grace"], ["south_catwalk"]),
        RouteEdge("C1_mouth", "C1_floor", 12.0, False, "any", 0.0, 0.85, ["B_iron"], ["fall_hazard"]),
        RouteEdge("C1_floor", "C1_mouth", 26.0, True, "quiet", 0.0, 0.55, ["B_iron", "recovery"], ["west_spiral"]),
        RouteEdge("C1_core", "C5_gallery", 22.0, False, "sprint", 0.0, 0.90, ["B_iron", "alarm"], ["east_spiral"]),
        RouteEdge("C5_gallery", "B5_control", 34.0, False, "sprint", 0.0, 0.20, ["chase_fade"], ["return_oneway"]),
        RouteEdge("B5_control", "A0_anchor", 38.0, True, "any", 0.0, 0.10, ["solo_or_duo_exit"], ["return_main"]),
    ]
    return LevelGraph("Expedition-01 Baseline", "A1_arcade", "C1_core", "A0_anchor", nodes, edges)


def mutate_add_b6_pump_room(g: LevelGraph) -> LevelGraph:
    """Candidate M1: Add B6 Pump Room (B3 -> B6 -> C1_mouth shortcut at noise cost)."""
    c = copy.deepcopy(g)
    c.name = "M1: +B6 Pump Room (Early Release Risk)"
    c.nodes["B6_pump"] = RoomNode("B6_pump", "B", "bypass", ["B_early_wake", "A_gaze_persist"], 0.0, 3)
    c.edges.append(RouteEdge("B3_trial", "B6_pump", 12.0, True, "quiet", 0.0, 0.45, ["B_early_wake"], ["shortcut", "risk"]))
    c.edges.append(RouteEdge("B6_pump", "C1_mouth", 14.0, True, "quiet", 0.0, 0.80, ["B_iron", "B_early_wake"], ["shortcut", "risk"]))
    return c


def mutate_add_c2_underdeck_ring(g: LevelGraph) -> LevelGraph:
    """Candidate M2: Add C2 Underdeck Ring (quiet low-level bypass with zero gaze check)."""
    c = copy.deepcopy(g)
    c.name = "M2: +C2 Underdeck Ring (No-Gaze Stealth)"
    c.nodes["C2_underdeck"] = RoomNode("C2_underdeck", "C", "bypass", ["B_iron", "unison", "single_lamp"], 0.0, 3)
    c.edges.append(RouteEdge("C1_mouth", "C2_underdeck", 19.0, True, "quiet", 4.0, 0.65, ["B_iron", "unison", "single_lamp"], ["stealth_bypass"]))
    c.edges.append(RouteEdge("C2_underdeck", "C1_core", 17.0, True, "quiet", 4.0, 0.70, ["B_iron", "single_lamp"], ["stealth_bypass"]))
    c.edges.append(RouteEdge("C2_underdeck", "C1_floor", 9.0, True, "quiet", 0.0, 0.50, ["B_iron", "recovery"], ["loop"]))
    return c


def mutate_unified_full(g: LevelGraph) -> LevelGraph:
    """Candidate M3: Combined B6 Pump Room + C2 Underdeck Ring + C5 mid-return valve branch."""
    c = mutate_add_c2_underdeck_ring(mutate_add_b6_pump_room(g))
    c.name = "M3: Unified Full (B6 + C2 + C5 Return Valve)"
    c.nodes["C5_gallery"].decision_points += 2
    c.edges.append(RouteEdge("C5_gallery", "A1_arcade", 30.0, False, "sprint", 0.0, 0.35, ["chase_fade", "B_iron"], ["return_alt"]))
    return c


def shortest_path(g: LevelGraph, src: str, dst: str) -> Tuple[float, List[str]]:
    dist: Dict[str, float] = {n: math.inf for n in g.nodes}
    prev: Dict[str, str] = {}
    dist[src] = 0.0
    unvisited: Set[str] = set(g.nodes.keys())
    while unvisited:
        u = min(unvisited, key=lambda k: dist[k])
        if dist[u] == math.inf or u == dst:
            break
        unvisited.remove(u)
        for e in g.edges:
            if e.src == u:
                v = e.dst
            elif e.bidirectional and e.dst == u:
                v = e.src
            else:
                continue
            alt = dist[u] + e.length_m
            if alt < dist[v]:
                dist[v] = alt
                prev[v] = u
    if dist[dst] == math.inf:
        return math.inf, []
    path = [dst]
    while path[-1] != src:
        path.append(prev[path[-1]])
    path.reverse()
    return dist[dst], path


def count_simple_routes(g: LevelGraph, src: str, dst: str, max_depth: int = 9) -> int:
    adj: Dict[str, List[str]] = {n: [] for n in g.nodes}
    for e in g.edges:
        adj[e.src].append(e.dst)
        if e.bidirectional:
            adj[e.dst].append(e.src)
    total = 0

    def dfs(u: str, visited: Set[str], depth: int) -> None:
        nonlocal total
        if depth > max_depth:
            return
        if u == dst:
            total += 1
            return
        for v in adj[u]:
            if v not in visited:
                visited.add(v)
                dfs(v, visited, depth + 1)
                visited.remove(v)

    dfs(src, {src}, 0)
    return total


def evaluate(g: LevelGraph) -> Dict[str, object]:
    """Compute deterministic structural KPIs & composite optimization score."""
    outbound_m, outbound_path = shortest_path(g, g.start, g.objective)
    return_m, return_path = shortest_path(g, g.objective, g.exit_node)
    total_decisions = sum(n.decision_points for n in g.nodes.values())
    c_decisions = sum(n.decision_points for n in g.nodes.values() if n.section in ("C", "RETURN"))
    multi_rule_edges = sum(1 for e in g.edges if len(e.rules_tested) >= 2)
    multi_rule_ratio = multi_rule_edges / max(1, len(g.edges))
    cyclomatic = len(g.edges) - len(g.nodes) + 1
    outbound_routes = count_simple_routes(g, g.start, g.objective, max_depth=8)
    c_section_routes = count_simple_routes(g, "C1_mouth", "C1_core", max_depth=4)
    # Hard safety gate: both outbound and return must be reachable, and recovery floor must reach C1_mouth
    rec_m, _ = shortest_path(g, "C1_floor", "C1_mouth")
    hard_pass = math.isfinite(outbound_m) and math.isfinite(return_m) and math.isfinite(rec_m)

    # Composite fitness (0..100): rewards late-game decisions, multi-rule tension, loop redundancy & route diversity
    score = (
        min(25.0, total_decisions * 0.95)
        + min(25.0, c_decisions * 2.1)
        + min(20.0, multi_rule_ratio * 42.0)
        + min(15.0, cyclomatic * 1.6)
        + min(15.0, math.log2(max(1, outbound_routes)) * 3.0)
    )
    if not hard_pass:
        score = 0.0

    return {
        "name": g.name,
        "hard_pass": hard_pass,
        "nodes": len(g.nodes),
        "edges": len(g.edges),
        "cyclomatic_loops": cyclomatic,
        "total_decisions": total_decisions,
        "late_game_decisions_C_return": c_decisions,
        "multi_rule_edges": multi_rule_edges,
        "multi_rule_ratio": round(multi_rule_ratio, 3),
        "outbound_shortest_m": round(outbound_m, 1),
        "return_shortest_m": round(return_m, 1),
        "est_walk_min_s": round((outbound_m + return_m) / 3.8, 1),
        "outbound_distinct_routes": outbound_routes,
        "shaft_distinct_routes": c_section_routes,
        "fitness_score": round(score, 2),
        "outbound_path": outbound_path,
        "return_path": return_path,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Programmatic iterative level-structure evaluator")
    parser.add_argument("--json", type=str, default="", help="Optional path to write JSON report")
    args = parser.parse_args()

    base = build_expedition_01_baseline()
    candidates = [
        base,
        mutate_add_b6_pump_room(base),
        mutate_add_c2_underdeck_ring(base),
        mutate_unified_full(base),
    ]
    results = [evaluate(c) for c in candidates]
    results_sorted = sorted(results, key=lambda r: r["fitness_score"], reverse=True)

    print("=== Programmatic Level Optimization Report ===")
    header = f"{'Variant':<44} | {'Score':>6} | {'Dec':>3} | {'C+Ret':>5} | {'Loops':>5} | {'2+Rule':>6} | {'C-Routes':>8}"
    print(header)
    print("-" * len(header))
    for r in results:
        print(
            f"{r['name']:<44} | {r['fitness_score']:>6.2f} | {r['total_decisions']:>3} | "
            f"{r['late_game_decisions_C_return']:>5} | {r['cyclomatic_loops']:>5} | "
            f"{r['multi_rule_edges']:>6} | {r['shaft_distinct_routes']:>8}"
        )
    print(f"\nTop recommended iteration: {results_sorted[0]['name']} (score {results_sorted[0]['fitness_score']})")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"candidates": results, "ranked": results_sorted}, f, ensure_ascii=False, indent=2)
        print(f"Wrote JSON report to {args.json}")


if __name__ == "__main__":
    main()
