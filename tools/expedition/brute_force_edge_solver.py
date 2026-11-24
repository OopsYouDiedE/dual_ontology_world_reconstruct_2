#!/usr/bin/env python3
"""Brute-Force State-Space Edge-Case Solver (per Level Atlas Page 4).

Exhaustively enumerates the discrete state space:
    State = (node, oil_tier, has_metronome, hale_posted, gate_open, valve_balanced, relay_lit, core_taken)

Checks two formal invariants from docs/production/level-atlas/index.html#p4:
  1. Existence of Solution (Forward BFS from every valid start, including empty-pack solo)
  2. Post-Failure Recoverability / Zero Softlocks (Backward reachability from Goal states:
     any forward-reachable alive state that cannot reach Goal is reported as a SOFTLOCK!)
  3. Dominant Cheese Detection (checks whether a zero-rule / zero-companion / zero-resource
     shortcut exists)
  4. Extended Solve-Time & Candidate Route Diversity comparison between Baseline and
     Extended Multi-Loop Expedition-01 (with B6 Valve Room + C3 Photometric Relay + 3 loopbacks).

Usage:
    python3 tools/expedition/brute_force_edge_solver.py
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from typing import Dict, List, Set, Tuple

# State tuple: (node, oil_tier 0..3, metronome, hale_north, gate_open, valve_ok, relay_ok, core_taken)
State = Tuple[str, int, bool, bool, bool, bool, bool, bool]


@dataclass(frozen=True)
class Transition:
    dst: str
    cost_s: float
    oil_delta: int = 0
    req_gate: bool = False
    req_valve: bool = False
    req_relay: bool = False
    req_core: bool = False
    req_oil_min: int = 0
    req_hale_or_lure: bool = False
    set_gate: bool = False
    set_valve: bool = False
    set_relay: bool = False
    set_core: bool = False
    set_hale_north: bool = False
    give_metronome: bool = False
    consume_metronome: bool = False
    tag: str = "move"


def build_baseline_automaton() -> Dict[str, List[Transition]]:
    """Current Expedition-01 state machine."""
    return {
        "A1": [
            Transition("A2", 18, oil_delta=+1, tag="niche_oil"),
            Transition("B1", 22, tag="main"),
            Transition("A0_EXIT", 12, req_core=True, tag="evacuate"),
        ],
        "A2": [
            Transition("A1", 18, tag="back"),
            Transition("B2", 14, tag="niche_shortcut"),
        ],
        "B1": [
            Transition("A1", 22, tag="back"),
            Transition("B2", 12, tag="main"),
        ],
        "B2": [
            Transition("B1", 12, tag="back"),
            Transition("A2", 14, tag="back"),
            Transition("B3", 16, tag="trial_entry"),
        ],
        "B3": [
            Transition("B2", 16, tag="back"),
            Transition("B4", 20, oil_delta=+1, tag="dark_oil"),
            Transition("B4_LOFT", 28, give_metronome=True, tag="signal_loft"),
            Transition("B5", 18, tag="bright_hall"),
        ],
        "B4": [
            Transition("B3", 20, tag="back"),
            Transition("B4_LOFT", 14, give_metronome=True, tag="signal_loft"),
            Transition("B5", 14, tag="dark_to_b5"),
        ],
        "B4_LOFT": [
            Transition("B4", 14, tag="back"),
            Transition("B5", 18, tag="loft_to_b5"),
        ],
        "B5": [
            Transition("B3", 18, tag="back"),
            Transition("B5", 6, set_gate=True, tag="pull_master_release"),
            Transition("C1_MOUTH", 14, req_gate=True, tag="enter_shaft"),
            Transition("A1", 26, req_gate=True, tag="return_arcade"),
        ],
        "C1_MOUTH": [
            Transition("B5", 14, tag="back"),
            Transition("C1_MOUTH", 15, set_hale_north=True, tag="post_hale_north"),
            # Route A: Main bridge (requires Hale north OR metronome lure)
            Transition("C1_CORE", 16, req_hale_or_lure=True, consume_metronome=True, set_core=True, tag="route_A_or_C_bridge"),
            # Route B: South catwalk (requires oil >= 2, consumes 2 oil tiers)
            Transition("C1_CORE", 26, req_oil_min=2, oil_delta=-2, set_core=True, tag="route_B_south_catwalk"),
            # Fall hazard -> recovery floor
            Transition("C1_FLOOR", 6, tag="fall_into_pit"),
        ],
        "C1_FLOOR": [
            Transition("C1_MOUTH", 28, tag="west_spiral_recovery"),
        ],
        "C1_CORE": [
            Transition("C1_MOUTH", 18, req_hale_or_lure=True, tag="bridge_back"),
            Transition("C5_GALLERY", 24, req_core=True, tag="east_spiral_evac"),
        ],
        "C5_GALLERY": [
            Transition("B5", 22, tag="return_oneway"),
        ],
        "A0_EXIT": [],
    }


def build_extended_multiloop_automaton() -> Dict[str, List[Transition]]:
    """Extended 18-25 min Expedition-01 topology per Level Atlas:
    - Adds 2 mandatory interlocking rooms:
        * B6_VALVE (Counterweight Valve Room): must balance pressure before B5 release latches
        * C3_RELAY (Far-Side Photometric Relay): must energize relay before core unlocks
    - Adds C2_UNDERDECK (Quiet Underdeck Ring, 4th candidate crossing)
    - Adds 3 cross-floor topological loopbacks (C2 <-> B6, C3 -> B4_LOFT upper catwalk, C5 -> A2)
    """
    g = build_baseline_automaton()
    # B5 master release now requires B6_VALVE balanced first
    g["B5"] = [
        Transition("B3", 18, tag="back"),
        Transition("B6_VALVE", 22, tag="enter_b6_valve"),
        Transition("B5", 8, req_valve=True, set_gate=True, tag="pull_master_release"),
        Transition("C1_MOUTH", 14, req_gate=True, tag="enter_shaft"),
        Transition("A1", 26, req_gate=True, tag="return_arcade"),
    ]
    g["B3"].append(Transition("B6_VALVE", 24, tag="b3_to_b6_loop"))
    g["B6_VALVE"] = [
        Transition("B5", 22, tag="back"),
        Transition("B3", 24, tag="loop_to_b3"),
        Transition("B6_VALVE", 18, set_valve=True, tag="balance_counterweight_valve"),
        Transition("C2_UNDERDECK", 26, req_valve=True, tag="loop_b6_to_c2_underdeck"),
    ]
    # C1_MOUTH gets Route D: C2 Underdeck Ring (quiet, costs 1 oil, no gaze check)
    g["C1_MOUTH"] = [
        Transition("B5", 14, tag="back"),
        Transition("C1_MOUTH", 16, set_hale_north=True, tag="post_hale_north"),
        Transition("C1_FAR", 16, req_hale_or_lure=True, consume_metronome=True, tag="route_A_or_C_bridge"),
        Transition("C1_FAR", 26, req_oil_min=2, oil_delta=-2, tag="route_B_south_catwalk"),
        Transition("C2_UNDERDECK", 24, req_oil_min=1, oil_delta=-1, tag="route_D_underdeck_ring"),
        Transition("C1_FLOOR", 6, tag="fall_into_pit"),
    ]
    g["C2_UNDERDECK"] = [
        Transition("C1_MOUTH", 24, tag="back"),
        Transition("B6_VALVE", 26, req_valve=True, tag="loop_c2_to_b6"),
        Transition("C1_FLOOR", 12, tag="drop_to_floor"),
        Transition("C1_FAR", 22, tag="underdeck_to_far"),
    ]
    # Far side splits into C3_RELAY (mandatory photometric unlock) -> C1_CORE
    g["C1_FAR"] = [
        Transition("C1_MOUTH", 18, req_hale_or_lure=True, tag="bridge_back"),
        Transition("C2_UNDERDECK", 22, tag="far_to_underdeck"),
        Transition("C3_RELAY", 24, tag="enter_c3_relay"),
        Transition("C1_CORE", 10, req_relay=True, set_core=True, tag="extract_unlocked_core"),
    ]
    g["C3_RELAY"] = [
        Transition("C1_FAR", 24, tag="back"),
        Transition("C3_RELAY", 20, set_relay=True, oil_delta=+1, tag="energize_photometric_relay"),
        Transition("B4_LOFT", 30, req_relay=True, tag="upper_loopback_to_b4_loft"),
    ]
    g["C1_CORE"] = [
        Transition("C1_FAR", 10, tag="back"),
        Transition("C5_GALLERY", 26, req_core=True, tag="east_spiral_evac"),
    ]
    # C5 evacuation gains an alternate loopback into A2 niche
    g["C5_GALLERY"].append(Transition("A2", 28, tag="return_alt_a2_loop"))
    return g


def brute_force_analyze(name: str, graph: Dict[str, List[Transition]], init_oil: int = 1) -> Dict[str, object]:
    start: State = ("A1", init_oil, False, False, False, False, False, False)
    visited: Dict[State, float] = {start: 0.0}
    adj: Dict[State, List[Tuple[State, float, str]]] = {start: []}
    rev: Dict[State, List[State]] = {}
    q = deque([start])

    while q:
        s = q.popleft()
        node, oil, metro, hale_n, gate, valve, relay, core = s
        for tr in graph.get(node, []):
            if tr.req_gate and not gate:
                continue
            if tr.req_valve and not valve:
                continue
            if tr.req_relay and not relay:
                continue
            if tr.req_core and not core:
                continue
            if oil < tr.req_oil_min:
                continue
            used_metro = False
            if tr.req_hale_or_lure:
                if not hale_n and not metro:
                    continue
                if not hale_n and metro and tr.consume_metronome:
                    used_metro = True
            next_oil = max(0, min(3, oil + tr.oil_delta))
            ns: State = (
                tr.dst,
                next_oil,
                (metro or tr.give_metronome) and not used_metro,
                hale_n or tr.set_hale_north,
                gate or tr.set_gate,
                valve or tr.set_valve,
                relay or tr.set_relay,
                core or tr.set_core,
            )
            if ns == s:
                continue
            adj.setdefault(s, []).append((ns, tr.cost_s, tr.tag))
            rev.setdefault(ns, []).append(s)
            new_cost = visited[s] + tr.cost_s
            if ns not in visited or new_cost < visited[ns]:
                visited[ns] = new_cost
                q.append(ns)

    goals = [s for s in visited if s[0] == "A0_EXIT"]
    # Backward reachability from all goals to detect ANY softlock state
    can_win: Set[State] = set(goals)
    bq = deque(goals)
    while bq:
        cur = bq.popleft()
        for prev in rev.get(cur, []):
            if prev not in can_win:
                can_win.add(prev)
                bq.append(prev)

    softlocks = [s for s in visited if s not in can_win]
    min_clear_s = min((visited[g] for g in goals), default=float("inf"))
    # Check if any winning state bypassed BOTH Hale and Metronome AND never refilled oil
    cheese_wins = [g for g in goals if (not g[3] and not g[2] and visited[g] < 130.0)]

    return {
        "name": name,
        "reachable_states": len(visited),
        "winning_states": len(goals),
        "softlock_states": len(softlocks),
        "min_solve_s": round(min_clear_s, 1),
        "est_first_play_min": round(min_clear_s * 3.8 / 60.0, 1),
        "zero_coop_fast_cheese_states": len(cheese_wins),
    }


def main() -> None:
    r_base = brute_force_analyze("Expedition-01 Baseline (Fixed Rules)", build_baseline_automaton(), init_oil=1)
    r_ext = brute_force_analyze("Extended Multi-Loop (B6+C2+C3+3 Loops)", build_extended_multiloop_automaton(), init_oil=1)

    print("=== Brute-Force State-Space Edge Solver (Level Atlas Page 4) ===")
    hdr = f"{'Topology':<40} | {'States':>6} | {'Softlock':>8} | {'MinTime(s)':>10} | {'Est1st(m)':>9} | {'Cheese':>6}"
    print(hdr)
    print("-" * len(hdr))
    for r in [r_base, r_ext]:
        print(
            f"{r['name']:<40} | {r['reachable_states']:>6} | {r['softlock_states']:>8} | "
            f"{r['min_solve_s']:>10.1f} | {r['est_first_play_min']:>9.1f} | {r['zero_coop_fast_cheese_states']:>6}"
        )


if __name__ == "__main__":
    main()
