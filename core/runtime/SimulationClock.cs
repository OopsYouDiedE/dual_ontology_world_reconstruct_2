using System.Text.Json;

namespace DuelView.Runtime;

public sealed record SimulationClockState(double Now,double PendingSeconds,double? DialogueEnd,double? RestEnd=null,double PhysicalSeconds=0);

/// <summary>Shared world time for actions and physical simulation. Dialogue deadlines
/// use the current rate. A host drains pending work before advancing another slice.</summary>
public sealed class SimulationClock
{
    private readonly double activeRate;
    private readonly double idleRate;
    private readonly double workRate;
    private readonly double maximumStep;
    private readonly double restRate;
    private readonly double restStep;
    private double? dialogueEnd;
    private double pendingSeconds;
    private double physicalSeconds;
    private double? restEnd;
    public bool Resting => restEnd.HasValue;
    public void RestUntil(double time) { if(time>Now)restEnd=time; }
    public double Now { get; private set; }
    public bool FastForwarding => dialogueEnd.HasValue;
    public double PendingSeconds => pendingSeconds+physicalSeconds;
    public double PendingPhysicalSeconds => physicalSeconds;
    public void ClearPendingSeconds(){pendingSeconds=0;physicalSeconds=0;}
    public void ClearUnsimulatedFastForward()=>pendingSeconds=0;
    public void SubmitPhysicalSeconds(double seconds)
    {
        if(!double.IsFinite(seconds)||seconds<0||seconds>60)throw new ArgumentOutOfRangeException(nameof(seconds));
        physicalSeconds+=seconds;
    }
    public void SubmitLogicalSeconds(double seconds)
    {
        if(!double.IsFinite(seconds)||seconds<0||seconds>60)throw new ArgumentOutOfRangeException(nameof(seconds));
        pendingSeconds+=seconds;
    }
    public double Rate(bool idle,bool working)=>restEnd.HasValue?restRate:working?workRate:idle?idleRate:activeRate;
    public SimulationClockState SaveState()=>new(Now,pendingSeconds,dialogueEnd,restEnd,physicalSeconds);
    public void RestoreState(SimulationClockState state)
    {
        if(!double.IsFinite(state.Now)||state.Now<0 || !double.IsFinite(state.PendingSeconds)||state.PendingSeconds<0 ||
           !double.IsFinite(state.PhysicalSeconds)||state.PhysicalSeconds<0||state.DialogueEnd is { } end && (!double.IsFinite(end)||end<state.Now))
            throw new InvalidDataException("Invalid simulation clock checkpoint.");
        Now=state.Now;pendingSeconds=state.PendingSeconds;physicalSeconds=state.PhysicalSeconds;dialogueEnd=state.DialogueEnd;restEnd=state.RestEnd;
    }

    public SimulationClock(JsonElement policy, double initialTime)
    {
        activeRate = policy.Get("active_game_seconds_per_second").Number(double.NaN);
        idleRate = policy.Get("idle_game_seconds_per_second").Number(double.NaN);
        workRate = policy.Get("work_game_seconds_per_second").Number(activeRate);
        maximumStep = policy.Get("maximum_game_seconds_per_slice").Number(double.NaN);
        restRate=policy.Get("rest_game_seconds_per_second").Number(activeRate);
        restStep=policy.Get("rest_maximum_game_seconds_per_slice").Number(maximumStep);
        if (!double.IsFinite(initialTime) || initialTime < 0 || !double.IsFinite(activeRate) || activeRate <= 0 ||
            !double.IsFinite(idleRate) || idleRate <= 0 || idleRate > activeRate || !double.IsFinite(workRate) || workRate<=0 || !double.IsFinite(maximumStep) || maximumStep <= 0)
            throw new InvalidDataException("Invalid DV clock policy.");
        Now = initialTime;
    }

    public void BeginDialogue(double duration)
    {
        if (dialogueEnd.HasValue) throw new InvalidOperationException("Dialogue already consumes clock time.");
        if (!double.IsFinite(duration) || duration <= 0 || !double.IsFinite(Now + duration)) throw new ArgumentOutOfRangeException(nameof(duration));
        dialogueEnd = Now + duration;
    }

    public double Step(double realSeconds, bool idle, bool paused, bool pendingWork, double nextEvent, bool working = false,bool physicalOnly=false)
    {
        if (!double.IsFinite(realSeconds) || realSeconds < 0 || double.IsNaN(nextEvent) || nextEvent < Now)
            throw new ArgumentOutOfRangeException(nameof(realSeconds));
        if (paused) return Now;
        // Navigation has already been simulated by Godot. Its seconds must not
        // be multiplied by work/rest rates or mixed with unexecuted fast-forward.
        if(physicalOnly)pendingSeconds=0;
        else pendingSeconds+=realSeconds*Rate(idle,working);
        if(pendingWork)return Now;
        var available=physicalSeconds+(physicalOnly?0:pendingSeconds);
        if(restEnd is { } wake)nextEvent=Math.Min(nextEvent,wake);
        if(dialogueEnd is { } boundary)nextEvent=Math.Min(nextEvent,boundary);
        var advance=Math.Max(0,Math.Min(Math.Min(available,restEnd.HasValue?restStep:maximumStep),nextEvent-Now));
        Now+=advance;
        var physical=Math.Min(physicalSeconds,advance);physicalSeconds-=physical;
        pendingSeconds=Math.Max(0,pendingSeconds-(advance-physical));
        if (dialogueEnd is { } end && Now >= end) dialogueEnd = null;
        if(restEnd is { } morning && Now>=morning){restEnd=null;pendingSeconds=0;}
        return Now;
    }
}

