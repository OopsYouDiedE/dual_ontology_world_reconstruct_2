using System.Diagnostics;
using System.Text.Json;

namespace DuelView.Runtime;

public sealed record WorldRuleCheckpoint(string Id,bool WasTrue,bool Fired,double? Due,long TimerGeneration);
public sealed record WorldRulesState(WorldRuleCheckpoint[] Rules,string[] Queue,long Evaluations,long Commits);

/// <summary>Dependency-indexed objective rules. Each rule is evaluated only after a
/// premise input changes. Explicit action laws are never registered implicitly.</summary>
public sealed class WorldRules
{
    private sealed record Entry(Rule Rule, bool Once, FieldKey Clock)
    {
        internal bool WasTrue;
        internal bool Fired;
        internal double Due = double.PositiveInfinity;
        internal long TimerGeneration;
    }
    private readonly FactStore world;
    private readonly double timeUnit;
    private readonly Dictionary<string, Entry> entries = new(StringComparer.Ordinal);
    private readonly Dictionary<FieldKey, HashSet<string>> readers = [];
    private readonly Queue<string> queue = [];
    private readonly HashSet<string> queued = new(StringComparer.Ordinal);
    private readonly PriorityQueue<(string Id, long Generation), double> timers = new();
    public bool Pending => queue.Count != 0;
    public long Evaluations { get; private set; }
    public long Commits { get; private set; }

    public WorldRulesState SaveState()=>new(entries.Select(pair=>new WorldRuleCheckpoint(pair.Key,pair.Value.WasTrue,pair.Value.Fired,
        double.IsFinite(pair.Value.Due)?pair.Value.Due:null,pair.Value.TimerGeneration)).ToArray(),queue.ToArray(),Evaluations,Commits);

    public void RestoreState(WorldRulesState state)
    {
        if(state.Rules is null || state.Queue is null || state.Evaluations<0 || state.Commits<0 || state.Rules.Length!=entries.Count ||
           state.Rules.Select(item=>item.Id).Distinct(StringComparer.Ordinal).Count()!=entries.Count || state.Queue.Distinct(StringComparer.Ordinal).Count()!=state.Queue.Length ||
           state.Queue.Any(id=>!entries.ContainsKey(id)))throw new InvalidDataException("Invalid world rule checkpoint.");
        foreach(var item in state.Rules)
            if(!entries.ContainsKey(item.Id) || item.TimerGeneration<0 || item.Due is { } due && (!double.IsFinite(due)||due<0))
                throw new InvalidDataException("Invalid world rule timer checkpoint.");
        queue.Clear();queued.Clear();timers.Clear();
        foreach(var item in state.Rules)
        {
            var entry=entries[item.Id];entry.WasTrue=item.WasTrue;entry.Fired=item.Fired;
            entry.Due=item.Due??double.PositiveInfinity;entry.TimerGeneration=item.TimerGeneration;
            if(item.Due is { } due)timers.Enqueue((item.Id,item.TimerGeneration),due);
        }
        foreach(var id in state.Queue)Enqueue(id);
        Evaluations=state.Evaluations;Commits=state.Commits;
    }

    internal WorldRules(FactStore world, double timeUnit) { this.world = world; this.timeUnit = timeUnit; }

    public void Register(string id, JsonElement adoption, FieldKey clock)
    {
        var rule = Rule.Compile(id, adoption, world.Subject);
        var trigger = adoption.Get("trigger").Text();
        if (trigger is not ("once" or "rising_edge"))
            throw new InvalidDataException("Objective automatic rule requires an explicit DV trigger: " + id);
        entries.Add(id, new(rule, trigger == "once", clock));
        foreach (var key in rule.Premise.Inputs.Distinct())
        {
            if (!readers.TryGetValue(key, out var set)) readers.Add(key, set = []);
            set.Add(id);
        }
        Schedule(id);
        Enqueue(id);
    }

    private void Enqueue(string id) { if (queued.Add(id)) queue.Enqueue(id); }

    internal void Changed(IEnumerable<FieldChange> changes)
    {
        foreach (var change in changes)
            if (readers.TryGetValue(change.Key, out var set)) foreach (var id in set) Enqueue(id);
    }

    private void Schedule(string id)
    {
        var entry = entries[id];
        var now = world.Read(entry.Clock)?.Value.Number() ?? 0;
        var next = entry.Once && entry.Fired ? double.PositiveInfinity : entry.Rule.Premise.WakeTimes(world.Read, entry.Clock)
            .Where(x => x > now).DefaultIfEmpty(double.PositiveInfinity).Min() * timeUnit;
        if (next == entry.Due) return;
        entry.Due = next;
        entry.TimerGeneration++;
        if (double.IsFinite(next)) timers.Enqueue((id, entry.TimerGeneration), next);
    }

    private void DiscardStaleTimers()
    {
        while (timers.TryPeek(out var timer, out _) && entries[timer.Id].TimerGeneration != timer.Generation) timers.Dequeue();
    }

    public double NextTime { get { DiscardStaleTimers(); return timers.TryPeek(out _, out var time) ? time : double.PositiveInfinity; } }

    internal void Wake(double now)
    {
        DiscardStaleTimers();
        while (timers.TryPeek(out var timer, out var time) && time <= now)
        {
            timers.Dequeue();
            if (entries[timer.Id].TimerGeneration == timer.Generation) { entries[timer.Id].Due = double.PositiveInfinity; Enqueue(timer.Id); }
            DiscardStaleTimers();
        }
    }

    internal void Step(double now, int budget, double milliseconds)
    {
        if (budget < 1 || !double.IsFinite(milliseconds) || milliseconds <= 0) throw new ArgumentOutOfRangeException(nameof(budget));
        var timer = Stopwatch.StartNew();
        for (var n = 0; n < budget && timer.Elapsed.TotalMilliseconds < milliseconds && queue.TryPeek(out var id); n++)
        {
            var entry = entries[id];
            if (entry.Once && entry.Fired) { queue.Dequeue(); queued.Remove(id); continue; }
            Evaluations++;
            var truth = entry.Rule.Premise.Evaluate(world.Read) == Truth.True;
            var fire = truth && !entry.WasTrue;
            if (!fire) { entry.WasTrue = truth; Schedule(id); queue.Dequeue(); queued.Remove(id); continue; }
            // Preview validates every effect and the postcondition before mutation.
            var writes = entry.Rule.Preview(world.Read, now);
            var changes = world.Apply(writes);
            queue.Dequeue(); queued.Remove(id);
            entry.WasTrue = truth;
            entry.Fired = true;
            Commits++;
            Changed(changes);
            Schedule(id);
        }
    }
}
