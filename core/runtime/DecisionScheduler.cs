using System.Diagnostics;
using System.Text.Json;

namespace DuelView.Runtime;

public sealed record ActionCandidate(string Id, Condition Gate, double Duration, double Score,
    JsonElement Declaration,Condition? RecognitionGate=null)
{
    public Condition Recognition=>RecognitionGate??Gate;
}
public sealed record DecisionIntent(string Path,string? Task,string? Step,string? PhysiologicalNeed,string Reason,string? PhysiologicalRoute=null,string? RouteAction=null,
    string? GoalAlgorithm=null,string[]? GoalSequence=null,string[]? GoalObjectives=null);
public sealed record Decision(string Actor, ActionCandidate Action, double StartedAt, double DueAt,long Execution=0,DecisionOption[]? Options=null,DecisionIntent? Intent=null);
public sealed record DecisionOption(string Action,double Score,DriveEvaluation Drive,double FailurePenalty=0,double GoalUtility=0,string PredictedReadiness="True");
public sealed record SchedulerSlice(int Evaluations, bool Pending);
public sealed record DecisionCheckpoint(string Actor,string Action,double StartedAt,double DueAt,long Execution,DecisionIntent? Intent=null);
public sealed record SchedulerSlotCheckpoint(string Actor,double Due,int Cursor,string? Best,double? BestScore,long Revision,bool Autonomous,bool Held,DriveState Needs,string[] Selection,double SelectionTime,DecisionCheckpoint? Running,TaskPlannerCheckpoint? Planning=null,ActionFailureCheckpoint[]? FailureMemory=null,JsonElement GoalPlanning=default);
public sealed record DecisionSchedulerState(SchedulerSlotCheckpoint[] Slots,long[] Ready,int Cursor,long NextExecution,long Evaluations);

/// <summary>Persistent round-robin cursors bound work independently of actor and action counts.
/// Gates read the actor's remembered facts, never the objective world.</summary>
public sealed class DecisionScheduler
{
    private sealed class Slot(ActorClient actor, ActionCandidate[] candidates, double now, double due)
    {
        internal ActorClient Actor = actor;
        internal ActionCandidate[] Candidates = candidates;
        internal double Due = due;
        internal int Cursor;
        internal ActionCandidate? Best;
        internal Decision? Running;
        internal long Revision = actor.KnowledgeRevision;
        internal bool Autonomous = true;
        internal bool Held;
        internal DriveCalculator Needs = new(actor.Declaration.Get("autonomy"), now);
        internal double BestScore = double.NegativeInfinity;
        internal DriveCandidateIndex Index=null!;
        internal ActionCandidate[] Selection=[];
        internal double SelectionTime;
        internal TaskPlanner Planner=null!;
        internal ActionFailureMemory Failures=null!;
        internal GoalPlanningAdapter Goals=null!;
    }

    private readonly List<Slot> slots = [];
    private readonly Dictionary<string, Slot> byActor = new(StringComparer.Ordinal);
    private readonly Queue<Decision> ready = [];
    private readonly double interval;
    private readonly double stagger;
    private readonly int candidatesPerDecision;
    private readonly int evaluationsPerSlice;
    private readonly double millisecondsPerSlice;
    private readonly double contentTimeUnit;
    private readonly int drivesPerDecision,candidatesPerDrive;
    private readonly double minimumUtility;
    private readonly Func<string,ActionCandidate,bool> eligible;
    private readonly Func<string,ActionCandidate,bool> modelEligible;
    private int cursor;
    private long nextExecution;
    public long Evaluations { get; private set; }
    public void SetAutonomy(string actor,bool enabled)=>byActor[actor].Autonomous=enabled;
    public DecisionSchedulerState SaveState()=>new(slots.Select(slot=>new SchedulerSlotCheckpoint(slot.Actor.Id,slot.Due,slot.Cursor,slot.Best?.Id,
        double.IsFinite(slot.BestScore)?slot.BestScore:null,slot.Revision,slot.Autonomous,slot.Held,slot.Needs.SaveState(),
        slot.Selection.Select(action=>action.Id).ToArray(),slot.SelectionTime,slot.Running is { } run?new(run.Actor,run.Action.Id,run.StartedAt,run.DueAt,run.Execution,run.Intent):null,slot.Planner.SaveState(),slot.Failures.Save(),slot.Goals.Save())).ToArray(),
        ready.Where(Owns).Select(item=>item.Execution).ToArray(),cursor,nextExecution,Evaluations);
    public IReadOnlyDictionary<long,Decision> RestoreState(DecisionSchedulerState state)
    {
        if(state.Slots is null || state.Ready is null || state.Slots.Length!=slots.Count || state.Cursor<0 || state.Cursor>=Math.Max(1,slots.Count) || state.NextExecution<0 || state.Evaluations<0 ||
           state.Slots.Select(item=>item.Actor).Distinct(StringComparer.Ordinal).Count()!=slots.Count || state.Ready.Distinct().Count()!=state.Ready.Length)
            throw new InvalidDataException("Invalid scheduler checkpoint.");
        var decisions=new Dictionary<long,Decision>();
        foreach(var item in state.Slots)
        {
            if(!byActor.TryGetValue(item.Actor,out var slot) || !double.IsFinite(item.Due)||item.Due<0 || item.Cursor<0 || item.Selection is null || item.Cursor>item.Selection.Length ||
               item.Revision<0 || !double.IsFinite(item.SelectionTime)||item.SelectionTime<0 || item.BestScore is { } score && !double.IsFinite(score))throw new InvalidDataException("Invalid scheduler slot checkpoint.");
            var actions=slot.Candidates.ToDictionary(action=>action.Id,StringComparer.Ordinal);
            if(item.Selection.Any(id=>!actions.ContainsKey(id)) || item.Best is { } best && !actions.ContainsKey(best))throw new InvalidDataException("Checkpoint references missing action.");
            if(item.Running is { } run)
            {
                if(run.Actor!=item.Actor || !actions.TryGetValue(run.Action,out var action) || run.Execution<1 || run.Execution>state.NextExecution || !double.IsFinite(run.StartedAt)||!double.IsFinite(run.DueAt)||run.StartedAt<0||run.DueAt<run.StartedAt ||
                   !decisions.TryAdd(run.Execution,new(run.Actor,action,run.StartedAt,run.DueAt,run.Execution,null,run.Intent)))throw new InvalidDataException("Invalid scheduled execution checkpoint.");
            }
        }
        if(state.Ready.Any(id=>!decisions.ContainsKey(id)))throw new InvalidDataException("Checkpoint has stale ready action.");
        foreach(var item in state.Slots)
        {
            var slot=byActor[item.Actor];var actions=slot.Candidates.ToDictionary(action=>action.Id,StringComparer.Ordinal);
            slot.Due=item.Due;slot.Cursor=item.Cursor;slot.Best=item.Best is { } best?actions[best]:null;slot.BestScore=item.BestScore??double.NegativeInfinity;
            slot.Revision=item.Revision;slot.Autonomous=item.Autonomous;slot.Held=item.Held;slot.Needs.RestoreState(item.Needs);
            slot.Planner.RestoreState(item.Planning);
            slot.Failures.Restore(item.FailureMemory);
            slot.Goals.Restore(item.GoalPlanning);
            slot.Selection=item.Selection.Select(id=>actions[id]).ToArray();slot.SelectionTime=item.SelectionTime;
            slot.Running=item.Running is { } running?decisions[running.Execution]:null;
        }
        ready.Clear();foreach(var id in state.Ready)ready.Enqueue(decisions[id]);cursor=state.Cursor;nextExecution=state.NextExecution;Evaluations=state.Evaluations;
        return decisions;
    }

    public DecisionScheduler(JsonElement policy,Func<string,ActionCandidate,bool>? eligibility=null,Func<string,ActionCandidate,bool>? modelEligibility=null)
    {
        eligible=eligibility??((_,_)=>true);
        modelEligible=modelEligibility??((_,_)=>true);
        interval = Positive(policy, "decision_interval_seconds");
        stagger = Positive(policy, "actor_stagger_seconds");
        candidatesPerDecision = PositiveInteger(policy, "candidates_per_decision");
        evaluationsPerSlice = PositiveInteger(policy, "evaluations_per_slice");
        millisecondsPerSlice = Positive(policy, "milliseconds_per_slice");
        contentTimeUnit = Positive(policy, "content_time_unit_seconds");
        drivesPerDecision=policy.Get("drives_per_decision").ValueKind==JsonValueKind.Undefined?candidatesPerDecision:PositiveInteger(policy,"drives_per_decision");
        candidatesPerDrive=policy.Get("candidates_per_drive").ValueKind==JsonValueKind.Undefined?1:PositiveInteger(policy,"candidates_per_drive");
        minimumUtility=policy.Get("minimum_action_utility").Number(double.NegativeInfinity);
    }

    private static double Positive(JsonElement policy, string field)
    {
        var value = policy.Get(field).Number(double.NaN);
        if (!double.IsFinite(value) || value <= 0) throw new InvalidDataException("Positive DV scheduling value required: " + field);
        return value;
    }

    private static int PositiveInteger(JsonElement policy, string field)
    {
        var value = Positive(policy, field);
        if (value != Math.Truncate(value) || value > int.MaxValue) throw new InvalidDataException("Integer budget required: " + field);
        return (int)value;
    }

    public void Register(ActorClient actor, IEnumerable<ActionCandidate> candidates, double now, bool autonomous = true)
    {
        ValidateTime(now);
        var items = candidates.ToArray();
        // The content catalog remains complete. Candidate evaluation is sliced below.
        if (items.Select(x => x.Id).Distinct(StringComparer.Ordinal).Count() != items.Length)
            throw new InvalidDataException("Duplicate action identity: " + actor.Id);
        foreach (var item in items)
            if (item.Id.Length == 0 || !double.IsFinite(item.Duration) || item.Duration <= 0 || !double.IsFinite(item.Score))
                throw new InvalidDataException("Invalid authored action: " + item.Id);
        var due = now + slots.Count * stagger;
        var slot = new Slot(actor, items, now, due) { Autonomous = autonomous };
        foreach(var item in items)slot.Needs.Validate(item);
        slot.Index=new(items,slot.Needs);
        slot.Failures=new(actor,items,contentTimeUnit);
        slot.Goals=new(actor,items,contentTimeUnit);
        slot.Planner=new(actor,items,slot.Needs,action=>slot.Running is null&&!slot.Held&&!actor.IsUpdating&&!actor.IsObserving&&eligible(actor.Id,action),contentTimeUnit,
            (action,time)=>slot.Failures.Penalty(action.Id,time));
        byActor.Add(actor.Id, slot);
        slots.Add(slot);
    }

    public SchedulerSlice Step(double now,Action<Decision>? onSelected=null)
    {
        ValidateTime(now);
        foreach(var item in slots)
        {
            item.Failures.Refresh(now);
            if(item.Needs.Tick(now))
            {
                item.Selection=[];item.Cursor=0;item.Best=null;item.BestScore=double.NegativeInfinity;
            }
        }
        var timer = Stopwatch.StartNew();
        var count = 0;
        var idleVisits = 0;
        // Continue the same fair rotation while useful candidate work remains.
        // A lone due actor may use the remaining fixed evaluation budget instead
        // of requiring a full world step for every candidate. One empty rotation
        // still ends the slice, and both the count and wall-clock budgets apply.
        while (slots.Count > 0 && count < Math.Min(evaluationsPerSlice, candidatesPerDecision) && idleVisits < slots.Count && timer.Elapsed.TotalMilliseconds < millisecondsPerSlice)
        {
            var slot = slots[cursor];
            cursor = (cursor + 1) % slots.Count;
            if (slot.Held || !slot.Autonomous || slot.Running is not null || slot.Due > now || slot.Actor.IsUpdating || slot.Actor.IsObserving)
            {idleVisits++;continue;}
            FieldKey[] changed=[];
            if (slot.Revision != slot.Actor.KnowledgeRevision)
            {
                changed=slot.Actor.View().Knowledge.Where(pair=>pair.Value.Revision>slot.Revision).Select(pair=>pair.Key).ToArray();
                slot.Cursor = 0;
                slot.Best = null;
                slot.BestScore = double.NegativeInfinity;
                slot.Revision = slot.Actor.KnowledgeRevision;
                slot.Selection=[];
            }
            if(slot.Selection.Length==0)
            {
                slot.SelectionTime=now;
                var frontier=slot.Planner.Frontier(now);
                var daily=slot.Index.Select(slot.Needs,now,candidatesPerDecision,drivesPerDecision,candidatesPerDrive,changed);
                slot.Goals.Evaluate(now,action=>eligible(slot.Actor.Id,action),action=>modelEligible(slot.Actor.Id,action),slot.Failures);
                var purposeful=slot.Goals.FirstAction is { } first?slot.Candidates.Where(action=>action.Id==first):[];
                slot.Selection=frontier.Concat(purposeful).Concat(daily).DistinctBy(action=>action.Id)
                    .Where(action=>action.Recognition.Evaluate(slot.Actor.Recall)==Truth.True).Take(candidatesPerDecision).ToArray();
            }
            if (slot.Cursor < slot.Selection.Length)
            {
                idleVisits=0;
                var candidate = slot.Selection[slot.Cursor++];
                count++;
                Evaluations++;
                if (!candidate.Declaration.Get("manual_only").Flag() && !candidate.Declaration.Get("physiology_route_only").Flag() && eligible(slot.Actor.Id,candidate) && candidate.Recognition.Evaluate(slot.Actor.Recall) == Truth.True)
                {
                    var score = Score(slot,candidate,slot.SelectionTime);
                    if (score > slot.BestScore) { slot.Best = candidate; slot.BestScore = score; }
                }
            }
            else idleVisits++;
            if (slot.Cursor < slot.Selection.Length) continue;
            var planned=slot.Planner.Choose(slot.Selection,slot.Best,slot.SelectionTime);
            if (planned is { } best && (slot.Planner.DirectedChoice||slot.BestScore>minimumUtility) && eligible(slot.Actor.Id,best))
            {
                var options=slot.Selection.Where(c=>!c.Declaration.Get("manual_only").Flag()&&eligible(slot.Actor.Id,c)&&c.Recognition.Evaluate(slot.Actor.Recall)==Truth.True)
                    .Select(c=>new DecisionOption(c.Id,Score(slot,c,slot.SelectionTime),slot.Needs.Evaluate(c,slot.SelectionTime),slot.Failures.Penalty(c.Id,slot.SelectionTime),slot.Goals.Score(c.Id),c.Gate.Evaluate(slot.Actor.Recall).ToString())).ToArray();
                var intent=slot.Planner.DirectedChoice?slot.Planner.Intent(best.Id):slot.Goals.Intent(best.Id)??slot.Planner.Intent(best.Id);
                var decision = new Decision(slot.Actor.Id, best, now, now + best.Duration,++nextExecution,options,intent);
                slot.Running = decision;
                // The session can reserve the chosen action immediately. Later actors
                // in this bounded pass then see the occupied slot in their eligibility
                // check instead of all choosing the same apparently free resource.
                if(onSelected is null)ready.Enqueue(decision);
                else onSelected(decision);
            }
            slot.Best = null;
            slot.BestScore = double.NegativeInfinity;
            slot.Cursor = 0;
            slot.Selection=[];
            // A long clock jump does not create a backlog of missed decisions.
            slot.Due = now + interval;
        }
        return new(count, slots.Any(x => !x.Held && x.Autonomous && x.Running is null && !x.Actor.IsUpdating && !x.Actor.IsObserving && x.Due <= now));
    }

    public bool TryTake(out Decision? decision)
    {
        var count=ready.Count;
        while(count-->0 && ready.TryDequeue(out decision))
        {
            if(!Owns(decision))continue;
            if(byActor[decision.Actor].Held){ready.Enqueue(decision);continue;}
            return true;
        }
        decision=null;return false;
    }

    internal bool Owns(Decision decision) => byActor.TryGetValue(decision.Actor, out var slot) && ReferenceEquals(slot.Running, decision);

    public double NextDecisionTime => slots.Where(x => !x.Held && x.Autonomous && x.Running is null && !x.Actor.IsUpdating && !x.Actor.IsObserving)
        .Select(x => x.Due).DefaultIfEmpty(double.PositiveInfinity).Min();

    public Decision Submit(string actor, string action, double now, bool enqueue = true)
    {
        ValidateTime(now);
        var slot = byActor[actor];
        if (slot.Held || slot.Running is not null || slot.Actor.IsUpdating || slot.Actor.IsObserving)
            throw new InvalidOperationException("Actor is occupied.");
        var candidate = slot.Candidates.SingleOrDefault(x => x.Id == action)
            ?? throw new InvalidOperationException("Unknown actor action.");
        if (!eligible(actor,candidate)) throw new InvalidOperationException("Action is unavailable at the actor's current position.");
        if (candidate.Recognition.Evaluate(slot.Actor.Recall) != Truth.True) throw new InvalidOperationException("Action is unavailable in actor knowledge.");
        slot.Planner.ManualChoice(action,now);slot.Planner.Frontier(now);
        var decision = new Decision(actor, candidate, now, now + candidate.Duration,++nextExecution,null,slot.Planner.Intent(candidate.Id,true));
        slot.Running = decision;
        slot.Cursor = 0;
        slot.Best = null;
        slot.BestScore = double.NegativeInfinity;
        slot.Selection=[];
        if (enqueue) ready.Enqueue(decision);
        return decision;
    }

    public void Complete(Decision decision, double now, bool succeeded = true, bool actualHostElapsed = false)
    {
        ValidateTime(now);
        var slot = byActor[decision.Actor];
        if (!ReferenceEquals(slot.Running, decision)) throw new InvalidOperationException("Stale action completion.");
        if (!actualHostElapsed && now < decision.DueAt) throw new InvalidOperationException("Action duration has not elapsed.");
        if (succeeded){slot.Needs.Complete(decision.Action, now);slot.Planner.Completed(decision,now);}
        slot.Running = null;
        slot.Due = now + interval;
    }

    public bool Cancel(Decision decision,double now)
    {
        ValidateTime(now);
        if(!Owns(decision))return false;
        var slot=byActor[decision.Actor];
        slot.Running=null;slot.Best=null;slot.Selection=[];slot.Cursor=0;
        slot.BestScore=double.NegativeInfinity;slot.Due=now+interval;
        return true;
    }

    public IReadOnlyDictionary<string,double> Needs(string actor,double now)=>byActor[actor].Needs.Snapshot(now);
    public IEnumerable<(string Actor,AffectEvent Event)> DrainAffectEvents()=>slots.SelectMany(slot=>slot.Needs.DrainEvents().Select(item=>(slot.Actor.Id,item)));
    public object Affect(string actor)=>new {emotion=byActor[actor].Needs.Emotion,buffs=byActor[actor].Needs.Buffs};
    public object Paths(string actor,double now)=>byActor[actor].Planner.View(now,byActor[actor].Autonomous);
    private double Score(Slot slot,ActionCandidate action,double now)=>slot.Needs.Score(action,now)+slot.Actor.GoalScore(action,now/contentTimeUnit)+slot.Goals.Score(action.Id)-slot.Failures.Penalty(action.Id,now);
    public object GoalAudit(string actor)=>byActor[actor].Goals.Audit();
    public object FailureAudit(string actor,double now)=>byActor[actor].Failures.Audit(now);
    internal ActionFailureCheckpoint? RecordOutcome(Decision decision,bool success,string reason,IEnumerable<FieldKey> basis,double now,string[]? blockedResources=null)
    {
        var slot=byActor[decision.Actor];
        return slot.Failures.Record(decision.Action,success,reason,basis,now,slot.Needs.Score(decision.Action,now)+slot.Actor.GoalScore(decision.Action,now/contentTimeUnit)+slot.Goals.Score(decision.Action.Id),blockedResources);
    }
    internal void Hold(string actor,bool held)=>byActor[actor].Held=held;
    public bool Available(string actor,string action)
    {
        var slot=byActor[actor];
        if(slot.Held || slot.Running is not null || slot.Actor.IsUpdating || slot.Actor.IsObserving)return false;
        var candidate=slot.Candidates.Single(candidate=>candidate.Id==action);
        return eligible(actor,candidate)&&candidate.Recognition.Evaluate(slot.Actor.Recall)==Truth.True;
    }
    public ActionCandidate Candidate(string actor,string action)=>byActor[actor].Candidates.Single(candidate=>candidate.Id==action);
    public DriveEvaluation EvaluateDrive(string actor,string action,double now)
    {
        var slot=byActor[actor];
        return slot.Needs.Evaluate(slot.Candidates.Single(candidate=>candidate.Id==action),now);
    }

    public void ReconfigureDrives(string actor,JsonElement policy,double now)
    {
        var slot=byActor[actor];
        var candidate=new DriveCalculator(policy,now);
        foreach(var action in slot.Candidates)candidate.Validate(action);
        slot.Needs.Reconfigure(policy,now);slot.Index=new(slot.Candidates,slot.Needs);
        slot.Selection=[];slot.Cursor=0;slot.Best=null;slot.BestScore=double.NegativeInfinity;
    }

    private static void ValidateTime(double now)
    {
        if (!double.IsFinite(now) || now < 0) throw new ArgumentOutOfRangeException(nameof(now));
    }
}
