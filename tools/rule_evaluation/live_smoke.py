"""Exercise the playable input path, not the witness snapshot player."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "mcp" / "game"))
import server  # noqa: E402


def rehearsal(room, action):
    run = server.Run(1,scene_key="rule_evaluation", eval_rehearse_warning=room)
    try:
        state = run.request("observe",timeout=50)["state"]
        assert state["notebook_visible"] and state["observation"]["warning"],state
        assert state["emergency_operation"]["op_type"] == action,state
        warning_tick = int(state["tick"])
        run.request("action",action="eval_notebook",frames=1,timeout=50)
        ended = run.request("action",action="eval_use",frames=22,timeout=50)["state"]
        assert ended["status"] == "RUNNING" and not ended["observation"]["warning"],ended
        assert ended["last_result"] == "OK",ended
        print(json.dumps({"renderer":"forward_plus","room":room,"input_path":f"notebook, E {action}",
                          "physical_ticks_elapsed":int(ended["tick"])-warning_tick,"session":run.id}),flush=True)
    finally:
        run.close()


def main():
    run = server.Run(1, scene_key="rule_evaluation")
    def ask(op, **kwargs):
        return run.request(op, timeout=50, **kwargs)["state"]
    try:
        start = ask("observe")
        assert start["notebook_visible"] and start["tick"] == 0
        assert start["observation"]["handbook"]["acquired_tick"] == 0
        assert not start["commissioning_notes"]
        assert ask("action",action="eval_hint")["commissioning_notes"]
        assert not ask("action",action="eval_hint")["commissioning_notes"]
        ask("action", action="eval_notebook")
        for _ in range(25):
            state = ask("action", action="eval_use", frames=10)
            if state["exit_open"]: break
        else: raise AssertionError(f"E never locked the timed cams: {state}")
        result = ask("action", action="eval_crouch", frames=28)
        assert result["observation"]["self"]["pose"] == "crouch", result
        result = ask("action", action="eval_left", frames=28)
        assert result["observation"]["self"]["yaw"] == 15, result
        result = ask("action", action="eval_right", frames=28)
        assert result["observation"]["self"]["yaw"] == 0,result
        result = ask("action", action="eval_crouch", frames=28)
        assert result["observation"]["self"]["pose"] == "stand",result

        def move_until(action, done):
            for _ in range(24):
                state = ask("action",action=action,frames=10)
                if done(state): return state
            raise AssertionError(f"{action} did not reach its mark: {state}")

        def xz(state, axis): return state["observation"]["self"]["pos"][axis]

        move_until("move_left", lambda state: xz(state,0) >= 2700)
        move_until("move_up", lambda state: xz(state,1) >= 6100)
        approach = move_until("move_right", lambda state: abs(xz(state,0)) < 480)
        assert approach["level"] == 1 and approach["exit_open"],approach
        ended = move_until("move_up", lambda state: state["level"] == 2)
        print(json.dumps({"renderer":"forward_plus","input_path":"notebook, latch, crouch, yaw, WASD portal crossing",
                          "room":int(ended["level"]),"tick":int(ended["tick"]),"session":run.id}))
    finally:
        run.close()
    rehearsal(4,"relieve")
    rehearsal(10,"emergency_stop")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
