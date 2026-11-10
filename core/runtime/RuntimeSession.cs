using System.Text.Json;
using DuelView.Core;
using DuelView.Dv;

namespace DuelView.Runtime;

public sealed record ActionInterruption(string Reason,string Label);
public sealed record ActionReceipt(string Actor, string Action, double Time, bool Committed, string Reason,long Execution=0,DecisionIntent? Intent=null,ActionInterruption? Interruption=null,ActionNarrative[]? Narrative=null);
public sealed record ActionOutcome(string Actor,string Action,long Execution,double StartedAt,double Time,bool Committed,string Reason,
    DecisionIntent? Intent,FieldChange[] Changes,Dictionary<string,double> NeedsBefore,Dictionary<string,double> NeedsAfter,
    ActionInterruption? Interruption=null,SavedFact[]? InterruptionBasis=null,ActionNarrative[]? Narrative=null,ActionFailureCheckpoint? LearnedFailure=null,
    ActionStartAttempt? StartAttempt=null);
public sealed record ActionStartAttempt(DecisionOption[] Options,DriveEvaluation Drive,JsonElement Audit);
public sealed record ActivityView(string Actor,string Action,long Execution,string Phase,double? WorkStartedAt,double? WorkEndsAt,bool HostCompleted);
public sealed record PhysicalPlacement(double X,double Y,double Z,double Yaw,string Room,double Time);
public sealed record JourneyView(PathPoint Position,double Distance,double Length,bool Arrived);
public sealed record ExecutionCheckpoint(long Execution,bool HostCompleted,string? ObservationToken,bool WorkAfterArrival,bool HostElapsed,
    double? WorkStartedAt,double? DueAt,bool CancelRequested,bool Dispatched,bool CompletionDeferred);
public sealed record CompletionCheckpoint(long Execution,double Due);
public sealed record StrategyBindingCheckpoint(long LastAttemptRevision,StrategyActivityState Activity);
public sealed record CompletedStrategyCheckpoint(long Execution,long Revision,CaseStrategyChoice[] Choices);
public sealed record ConversationCheckpoint(ConversationState State,JsonElement Declaration,Dictionary<string,double> Holds,string[] Locks);
public sealed record LogicalDoorState(double Angle,double Target,bool Moving,double CloseRemaining);
public sealed record RuntimeSessionState(int Version,FactStoreState World,ActorClientState[] Actors,SimulationClockState Clock,
    WorldRulesState Rules,DecisionSchedulerState Scheduler,ReservationCheckpoint[] Reservations,ExecutionCheckpoint[] Executions,
    CompletionCheckpoint[] Completions,long[] Dispatched,long[] Cancellations,ActionReceipt[] Receipts,
    Dictionary<long,PathJourneyState> Journeys,Dictionary<string,PhysicalPlacement> Placements,Dictionary<string,StrategyBindingCheckpoint> Strategies,
    CompletedStrategyCheckpoint[] CompletedStrategies,ConversationCheckpoint? Conversation,Dictionary<string,LogicalDoorState> Doors,long NextConversation,long NextEvidence,int ActorCursor,int StrategyCursor,
    MechanicsCheckpoint? Mechanics=null,SpatialAuthorityCheckpoint? Spatial=null,Dictionary<string,double>? ActionCooldowns=null,ActionOutcome[]? ActionOutcomes=null);

/// <summary>Serial session owner. The host executes presentation and submits real
/// completion. No action outcome is committed merely because a timer expired.</summary>
public sealed partial class RuntimeSession
{
    private sealed record Execution(Decision Decision, Effect[] Effects, Condition CompletionGate, Condition? Postcondition, bool HostRequired)
    {
        internal bool HostCompleted;
        internal string? ObservationToken;
        internal bool WorkAfterArrival;
        internal bool HostElapsed;
        internal double? WorkStartedAt;
        internal double DueAt=Decision.DueAt;
        internal bool CancelRequested;
        internal bool Dispatched;
        internal bool CompletionDeferred;
    }
    private readonly Dictionary<string, ActorClient> actors = new(StringComparer.Ordinal);
    private readonly List<(string Actor,JsonElement Data,Condition WorldGate,Condition KnowledgeGate,FieldKey[] Fields)> sensoryEvents=[];
    private readonly Dictionary<string, Execution> running = new(StringComparer.Ordinal);
    private readonly PriorityQueue<Execution, double> completions = new();
    private readonly Queue<ActionReceipt> receipts = [];
    private readonly Queue<ActionOutcome> actionOutcomes=[];
    private readonly Dictionary<string,double> actionCooldowns=new(StringComparer.Ordinal);
    private readonly Queue<Decision> dispatched = [];
    private readonly Queue<Decision> cancellations = [];
    private readonly int inferenceBudget;
    private readonly int workBudget;
    private readonly double sliceMilliseconds;
    private readonly FieldKey? clockField;
    private readonly double contentTimeUnit;
    private double observationHorizon=double.PositiveInfinity;
    private readonly HashSet<string> observationKinds;
    private PerceptionBindings perception = new(JsonSerializer.SerializeToElement(Array.Empty<object>()));
    private readonly HashSet<FieldKey> hostPhysicalBindings=[];
    private long nextEvidence;
    private int actorCursor;
    private string[] actorOrder = [];
    private readonly Dictionary<string,double> conversationHolds = new(StringComparer.Ordinal);
    private readonly HashSet<string> conversationLocks = new(StringComparer.Ordinal);
    private ConversationSession? conversation;
    private JsonElement conversationDeclaration;
    private readonly Dictionary<string,Condition> conversationGates=new(StringComparer.Ordinal);
    private readonly Dictionary<string,FieldKey> incapacitation=new(StringComparer.Ordinal);
    private long nextConversation;
    public FactStore World { get; } = new("world");
    private DecisionScheduler Scheduler { get; }
    public long DecisionEvaluations => Scheduler.Evaluations;
    public bool HasPendingDecisionWork { get; private set; }
    public SimulationClock Clock { get; }
    public RoomResidency Rooms { get; }
    public WorldRules Rules { get; }
    public SlotReservations Reservations { get; }=new();
    private readonly Dictionary<string,PhysicalPlacement> placements=new(StringComparer.Ordinal);
    private readonly Dictionary<string,LogicalDoorState> logicalDoors=new(StringComparer.Ordinal);
    public IReadOnlyDictionary<string,LogicalDoorState> LogicalDoors=>logicalDoors;
    public void ReportDoor(string id,LogicalDoorState state)
    {
        if(string.IsNullOrWhiteSpace(id)||!double.IsFinite(state.Angle)||!double.IsFinite(state.Target)||!double.IsFinite(state.CloseRemaining)||state.CloseRemaining<0 || Math.Abs(state.Angle)>180 || Math.Abs(state.Target)>180)
            throw new InvalidDataException("Invalid logical door state.");
        logicalDoors[id]=state;
    }
    private sealed record PresenceGroup(string[] Members,HashSet<string> Rooms,FieldKey Result,double[]? Center,double Radius,bool Latch);
    private readonly List<PresenceGroup> presenceGroups=[];
    private sealed record Accumulator(FieldKey Active,FieldKey Present,FieldKey Amount,double Rate);
    private readonly List<Accumulator> accumulators=[];
    private readonly Dictionary<long,PathJourney> journeys=[];
    public void ConfigureAccumulators(JsonElement declarations)
    {
        foreach(var declaration in declarations.Items())
        {
            if(accumulators.Count>=32)throw new InvalidDataException("Accumulator budget exceeded.");
            var rate=declaration.Get("per_game_second").Number(double.NaN);
            var active=FieldKey.Read(declaration.Get("active"),"world");
            var present=FieldKey.Read(declaration.Get("present"),"world");
            var amount=FieldKey.Read(declaration.Get("amount"),"world");
            if(!double.IsFinite(rate)||rate<=0 || World.Read(amount) is not {Known:true,Conflicted:false} initial || !double.IsFinite(initial.Value.Number(double.NaN)) || initial.Value.Number()<0)
                throw new InvalidDataException("Invalid objective accumulator declaration.");
            accumulators.Add(new(active,present,amount,rate));
        }
    }
    private readonly Dictionary<string,(CaseTheory theory,JsonElement declaration)> deductions=new(StringComparer.Ordinal);
    private sealed class StrategyBinding(string actor,StrategyActivity activity,FieldKey output,FieldKey? completion,bool publish=false)
    {
        internal readonly string Actor=actor;
        internal readonly StrategyActivity Activity=activity;
        internal readonly FieldKey Output=output;
        internal readonly FieldKey? Completion=completion;
        internal readonly bool Publish=publish;
        internal long LastAttemptRevision=-1;
    }
    private readonly Dictionary<string,StrategyBinding> strategyBindings=new(StringComparer.Ordinal);
    private readonly Dictionary<long,(long Revision,IReadOnlyList<CaseStrategyChoice> Choices)> completedStrategies=[];
    private int strategyCursor;
    public object? LastStrategy { get; private set; }
    public Decision? DecisionFor(long execution)=>running.Values.Select(item=>item.Decision).SingleOrDefault(item=>item.Execution==execution);
    public RuntimeSessionState SaveState()
    {
        var actions=running.Values.Select(item=>new ExecutionCheckpoint(item.Decision.Execution,item.HostCompleted,item.ObservationToken,
            item.WorkAfterArrival,item.HostElapsed,item.WorkStartedAt,double.IsFinite(item.DueAt)?item.DueAt:null,item.CancelRequested,item.Dispatched,item.CompletionDeferred)).ToArray();
        return new(4,World.SaveState(),actors.Values.Select(actor=>actor.SaveState()).ToArray(),Clock.SaveState(),Rules.SaveState(),Scheduler.SaveState(),Reservations.SaveState(),actions,
            completions.UnorderedItems.Select(item=>new CompletionCheckpoint(item.Element.Decision.Execution,item.Priority)).ToArray(),
            dispatched.Where(item=>running.TryGetValue(item.Actor,out var run)&&ReferenceEquals(run.Decision,item)).Select(item=>item.Execution).ToArray(),
            cancellations.Where(item=>running.TryGetValue(item.Actor,out var run)&&ReferenceEquals(run.Decision,item)).Select(item=>item.Execution).ToArray(),receipts.ToArray(),
            journeys.ToDictionary(item=>item.Key,item=>item.Value.SaveState()),new(placements,StringComparer.Ordinal),
            strategyBindings.ToDictionary(item=>item.Key,item=>new StrategyBindingCheckpoint(item.Value.LastAttemptRevision,item.Value.Activity.SaveState()),StringComparer.Ordinal),
            completedStrategies.Select(item=>new CompletedStrategyCheckpoint(item.Key,item.Value.Revision,item.Value.Choices.ToArray())).ToArray(),
            conversation is null?null:new(conversation.SaveState(),conversationDeclaration.Clone(),new(conversationHolds,StringComparer.Ordinal),conversationLocks.ToArray()),new(logicalDoors,StringComparer.Ordinal),
            nextConversation,nextEvidence,actorCursor,strategyCursor,SaveMechanics(),SaveSpatial(),new(actionCooldowns,StringComparer.Ordinal),actionOutcomes.ToArray());
    }
    public void RestoreState(RuntimeSessionState state)
    {
        if(state.Version is not (1 or 2 or 3 or 4) || state.Version>=2&&state.Mechanics is null || state.Version>=3&&state.Spatial is null || state.Version>=4&&(state.ActionCooldowns is null||state.ActionOutcomes is null) || state.Actors is null || state.Actors.Length!=actors.Count || state.Actors.Select(item=>item.Actor).Distinct(StringComparer.Ordinal).Count()!=actors.Count ||
           state.Actors.Any(item=>!actors.ContainsKey(item.Actor)) || state.Executions is null || state.Completions is null || state.Dispatched is null || state.Cancellations is null || state.Receipts is null ||
           state.Journeys is null || state.Placements is null || state.Strategies is null || state.CompletedStrategies is null || state.Doors is null || state.NextConversation<0 || state.NextEvidence<0 || state.StrategyCursor<0 || state.ActorCursor<0 || state.ActorCursor>=Math.Max(1,actorOrder.Length) ||
           state.Strategies.Count!=strategyBindings.Count || state.Strategies.Keys.Any(key=>!strategyBindings.ContainsKey(key)))
            throw new InvalidDataException("Incompatible runtime checkpoint.");
        World.RestoreState(state.World);foreach(var actor in state.Actors)actors[actor.Actor].RestoreState(actor);
        Clock.RestoreState(state.Clock);Rules.RestoreState(state.Rules);var decisions=Scheduler.RestoreState(state.Scheduler);
        Reservations.RestoreState(state.Reservations);
        running.Clear();var executions=new Dictionary<long,Execution>();
        foreach(var item in state.Executions)
        {
            if(!decisions.TryGetValue(item.Execution,out var decision) || executions.ContainsKey(item.Execution) || running.ContainsKey(decision.Actor) ||
               item.WorkStartedAt is { } work && (!double.IsFinite(work)||work<0) || item.DueAt is { } due && (!double.IsFinite(due)||due<0))
                throw new InvalidDataException("Invalid runtime execution checkpoint.");
            var declaration=decision.Action.Declaration;
            var gate=declaration.Get("objective_gate").ValueKind==JsonValueKind.Object?Condition.Compile(declaration.Get("objective_gate"),World.Subject):new Condition.Constant(Truth.True);
            var effects=declaration.Get("effects").Items().Select(effect=>Effect.Compile(effect,World.Subject)).ToArray();
            var post=declaration.Get("objective_postcondition").ValueKind==JsonValueKind.Object?Condition.Compile(declaration.Get("objective_postcondition"),World.Subject):null;
            var execution=new Execution(decision,effects,gate,post,declaration.Get("requires_host_completion").Flag()) {
                HostCompleted=item.HostCompleted,ObservationToken=item.ObservationToken,WorkAfterArrival=item.WorkAfterArrival,HostElapsed=item.HostElapsed,
                WorkStartedAt=item.WorkStartedAt,DueAt=item.DueAt??double.PositiveInfinity,CancelRequested=item.CancelRequested,Dispatched=item.Dispatched,CompletionDeferred=item.CompletionDeferred};
            if(execution.WorkAfterArrival!= (execution.HostRequired&&declaration.Get("timing").Get("work_after_arrival").Flag()) ||
               execution.HostElapsed!= (execution.HostRequired&&declaration.Get("timing").Get("host_elapsed").Flag()))throw new InvalidDataException("Execution timing no longer matches content.");
            executions.Add(item.Execution,execution);running.Add(decision.Actor,execution);
        }
        RestoreSpatial(state.Spatial,decisions);
        if(state.Completions.Any(item=>!executions.ContainsKey(item.Execution)||!double.IsFinite(item.Due)||item.Due<0) ||
           state.Dispatched.Any(id=>!executions.ContainsKey(id)) || state.Cancellations.Any(id=>!executions.ContainsKey(id)) || state.Journeys.Keys.Any(id=>!executions.ContainsKey(id)))
            throw new InvalidDataException("Checkpoint contains an orphaned execution.");
        completions.Clear();foreach(var item in state.Completions)completions.Enqueue(executions[item.Execution],item.Due);
        dispatched.Clear();foreach(var id in state.Dispatched)dispatched.Enqueue(executions[id].Decision);
        cancellations.Clear();foreach(var id in state.Cancellations)cancellations.Enqueue(executions[id].Decision);
        receipts.Clear();foreach(var receipt in state.Receipts)receipts.Enqueue(receipt);
        actionOutcomes.Clear();foreach(var outcome in state.ActionOutcomes??[])actionOutcomes.Enqueue(outcome);
        var actionIds=actors.Values.SelectMany(actor=>actor.Declaration.Get("actions").Items().Select(action=>action.Get("id").Text())).ToHashSet(StringComparer.Ordinal);
        actionCooldowns.Clear();foreach(var item in state.ActionCooldowns??[])
        {
            if(!actionIds.Contains(item.Key)||!double.IsFinite(item.Value)||item.Value<0)throw new InvalidDataException("Invalid action cooldown checkpoint.");
            actionCooldowns.Add(item.Key,item.Value);
        }
        journeys.Clear();foreach(var item in state.Journeys)journeys.Add(item.Key,PathJourney.RestoreState(item.Value));
        placements.Clear();foreach(var item in state.Placements)
        {
            var p=item.Value;if(!actors.ContainsKey(item.Key)||!double.IsFinite(p.X)||!double.IsFinite(p.Y)||!double.IsFinite(p.Z)||!double.IsFinite(p.Yaw)||!double.IsFinite(p.Time)||p.Time<0)throw new InvalidDataException("Invalid checkpoint placement.");
            placements.Add(item.Key,p);
        }
        foreach(var item in state.Strategies){strategyBindings[item.Key].LastAttemptRevision=item.Value.LastAttemptRevision;strategyBindings[item.Key].Activity.RestoreState(item.Value.Activity);}
        completedStrategies.Clear();foreach(var item in state.CompletedStrategies)
        {
            if(!executions.ContainsKey(item.Execution)||item.Revision<0||item.Choices is null || !completedStrategies.TryAdd(item.Execution,(item.Revision,item.Choices)))
                throw new InvalidDataException("Invalid completed strategy checkpoint.");
        }
        conversation=null;conversationHolds.Clear();conversationLocks.Clear();
        if(state.Conversation is { } saved)
        {
            if(saved.State.Id>state.NextConversation || saved.Declaration.ValueKind!=JsonValueKind.Object || saved.Holds is null || saved.Locks is null ||
               saved.Locks.Length!=2 || saved.Locks.Distinct(StringComparer.Ordinal).Count()!=2 ||
               !saved.Locks.Contains(saved.State.Initiator,StringComparer.Ordinal) || !saved.Locks.Contains(saved.State.Target,StringComparer.Ordinal) ||
               saved.Locks.Any(id=>!actors.ContainsKey(id)) || saved.Holds.Any(pair=>!saved.Locks.Contains(pair.Key,StringComparer.Ordinal)||!double.IsFinite(pair.Value)||pair.Value<0||pair.Value>Clock.Now))
                throw new InvalidDataException("Invalid conversation locks checkpoint.");
            conversation=ConversationSession.RestoreState(saved.State,saved.Declaration);conversationDeclaration=saved.Declaration.Clone();
            foreach(var item in saved.Holds)conversationHolds.Add(item.Key,item.Value);conversationLocks.UnionWith(saved.Locks);
        }
        logicalDoors.Clear();foreach(var item in state.Doors)ReportDoor(item.Key,item.Value);
        nextConversation=state.NextConversation;nextEvidence=state.NextEvidence;actorCursor=state.ActorCursor;strategyCursor=state.StrategyCursor;
        RestoreMechanics(state.Mechanics,executions.Keys.ToHashSet());
    }
    public void ConfigureStrategy(string source,JsonElement declaration)
    {
        var actor=declaration.Get("actor").Text();var action=declaration.Get("action").Text();
        if(!actors.TryGetValue(actor,out var client)||action.Length==0||strategyBindings.Count>=16)
            throw new InvalidDataException("Invalid timed strategy actor, action or budget.");
        var data=DvScriptReader.Parse(source).GetProperty("data");
        var profileId=declaration.Get("profile").Text(actor);
        var profile=data.GetProperty("case_strategy").GetProperty("actors").EnumerateArray().Single(x=>x.GetProperty("actor").GetString()==profileId);
        var mappings=data.GetProperty("case_mind_evidence").GetProperty("mappings");
        var completion=declaration.Get("completion_output");
        var binding=new StrategyBinding(actor,new StrategyActivity(client,CaseTheory.Parse(source),profile,mappings,contentTimeUnit,declaration.Get("activity_evidence")),FieldKey.Read(declaration.Get("output"),actor),completion.ValueKind==JsonValueKind.Object?FieldKey.Read(completion,actor):null);
        if(!strategyBindings.TryAdd(action,binding))throw new InvalidDataException("Duplicate timed strategy action: "+action);
    }
    public object? LastDeduction { get; private set; }
    public void ConfigureDeduction(string source,JsonElement declaration)
    {
        var action=declaration.Get("action").Text();
        if(action.Length==0 || !deductions.TryAdd(action,(CaseTheory.Parse(source),declaration.Clone())))
            throw new InvalidDataException("Duplicate or missing deduction action.");
    }
    public PhysicalPlacement? Placement(string actor)=>placements.GetValueOrDefault(actor);
    public bool BeginJourney(Decision decision,IEnumerable<PathPoint> route)
    {
        if(!Current(decision,out var execution)||!execution!.HostRequired||execution.CancelRequested||journeys.ContainsKey(decision.Execution))return false;
        var points=route.ToArray();
        if(!placements.TryGetValue(decision.Actor,out var location)||points.Length<2 ||
           points[0].DistanceTo(new(location.X,location.Y,location.Z))>0.25)return false;
        journeys.Add(decision.Execution,new PathJourney(points));
        return true;
    }
    public JourneyView AdvanceJourney(Decision decision,double elapsed,double speed)
    {
        if(!Current(decision,out var execution)||execution!.CancelRequested||!journeys.TryGetValue(decision.Execution,out var journey))
            throw new InvalidOperationException("Journey is not active.");
        journey.Advance(elapsed,speed);return new(journey.Position,journey.Distance,journey.Length,journey.Arrived);
    }
    public PathPoint PreviewJourney(Decision decision,double elapsed,double speed)
    {
        if(!Current(decision,out var execution)||execution!.CancelRequested||!journeys.TryGetValue(decision.Execution,out var journey))
            throw new InvalidOperationException("Journey is not active.");
        return journey.Preview(elapsed,speed);
    }
    public bool EndJourney(Decision decision)
    {
        if(!Current(decision,out _)||!journeys.Remove(decision.Execution))return false;
        return true;
    }
    public void ReportPlacement(string actor,double x,double y,double z,double yaw,string room)
    {
        if(!actors.ContainsKey(actor))throw new InvalidOperationException("Unknown physical actor.");
        if(!double.IsFinite(x)||!double.IsFinite(y)||!double.IsFinite(z)||!double.IsFinite(yaw))
            throw new ArgumentOutOfRangeException(nameof(x));
        var hadPrior=placements.TryGetValue(actor,out var prior);
        var roomChanged=!hadPrior||prior!.Room!=room;
        placements[actor]=new(x,y,z,yaw,room,Clock.Now);
        var radiusChanged=hadPrior && presenceGroups.Any(group=>group.Center is not null && group.Members.Contains(actor,StringComparer.Ordinal)
            && InRadius(prior!,group)!=InRadius(placements[actor],group));
        if(roomChanged||radiusChanged)UpdatePresenceGroups();
    }
    public void ConfigurePresenceGroups(JsonElement declarations)
    {
        foreach(var declaration in declarations.Items())
        {
            if(presenceGroups.Count>=32)throw new InvalidDataException("Presence group budget exceeded.");
            var members=declaration.Get("members").Items().Select(x=>x.Text()).ToArray();
            var rooms=declaration.Get("rooms").Items().Select(x=>x.Text()).ToHashSet(StringComparer.Ordinal);
            if(members.Length is <1 or >32 || members.Distinct(StringComparer.Ordinal).Count()!=members.Length || members.Any(id=>!actors.ContainsKey(id)) || rooms.Count is <1 or >32)
                throw new InvalidDataException("Invalid presence group members or room budget.");
            var center=declaration.Get("center").Items().Select(x=>x.Number(double.NaN)).ToArray();
            var radius=declaration.Get("radius_m").Number(0);
            if(center.Length!=0 && (center.Length!=3 || center.Any(x=>!double.IsFinite(x)) || !double.IsFinite(radius) || radius<=0))
                throw new InvalidDataException("Invalid presence group radius.");
            var mode=declaration.Get("mode").Text("latched");
            if(mode is not ("latched" or "current"))throw new InvalidDataException("Invalid presence group mode.");
            presenceGroups.Add(new(members,rooms,FieldKey.Read(declaration.Get("result"),"world"),center.Length==0?null:center,radius,mode=="latched"));
        }
        UpdatePresenceGroups();
    }
    private void UpdatePresenceGroups()
    {
        foreach(var group in presenceGroups)
        {
            var old=World.Read(group.Result);
            if(group.Latch && old is {Known:true} && old.Value.ValueKind==JsonValueKind.True)continue;
            var present=group.Members.All(id=>placements.TryGetValue(id,out var place)&&group.Rooms.Contains(place.Room)&&InRadius(place,group));
            if(old is {Known:true,Conflicted:false} && old.Value.ValueKind==(present?JsonValueKind.True:JsonValueKind.False))continue;
            Rules.Changed(World.Apply(new Dictionary<FieldKey,Fact> { [group.Result]=new(JsonSerializer.SerializeToElement(present),true,false,1,ContentTime,0) }));
        }
    }
    private static bool InRadius(PhysicalPlacement place,PresenceGroup group)=>group.Center is null ||
        Math.Pow(place.X-group.Center[0],2)+Math.Pow(place.Y-group.Center[1],2)+Math.Pow(place.Z-group.Center[2],2)<=group.Radius*group.Radius;
    public double ContentTime => Clock.Now / contentTimeUnit;
    public void ConfigureObservationHorizon(double gameMinutes)
    {
        if(!double.IsFinite(gameMinutes)||gameMinutes<=ContentTime)throw new InvalidDataException("Invalid observation time boundary.");
        observationHorizon=gameMinutes*contentTimeUnit;
    }

    public ConversationView? Conversation => conversation?.View;
    public JsonElement ConversationDeclaration => conversation is null?default:conversationDeclaration.Clone();
    public bool ConversationAvailable(string initiator,JsonElement declaration)
    {
        if(Incapacitated(initiator) || Incapacitated(declaration.Get("target").Text()))return false;
        var precondition=declaration.Get("precondition");
        var id=declaration.Get("id").Text();
        if(precondition.ValueKind!=JsonValueKind.Undefined)
        {
            var key=id+"/initiator/"+initiator;
            if(!conversationGates.TryGetValue(key,out var gate))conversationGates[key]=gate=Condition.Compile(precondition,initiator);
            if(gate.Evaluate(actors[initiator].Recall)!=Truth.True)return false;
        }
        var targetCondition=declaration.Get("target_precondition");
        if(targetCondition.ValueKind==JsonValueKind.Undefined)return true;
        var target=declaration.Get("target").Text();
        if(!actors.TryGetValue(target,out var targetActor))return false;
        var targetKey=id+"/target/"+target;
        if(!conversationGates.TryGetValue(targetKey,out var targetGate))conversationGates[targetKey]=targetGate=Condition.Compile(targetCondition,target);
        return targetGate.Evaluate(targetActor.Recall)==Truth.True;
    }
    public ConversationView StartConversation(string initiator,string target,JsonElement declaration)
    {
        if(!ConversationAvailable(initiator,declaration))throw new InvalidOperationException("Conversation knowledge condition is not satisfied.");
        if(conversation is not null || !actors.ContainsKey(initiator) || !actors.ContainsKey(target) ||
           (running.TryGetValue(initiator,out var initiatorAction) && initiatorAction.CancelRequested) ||
           (running.TryGetValue(target,out var targetAction) && targetAction.CancelRequested))
            throw new InvalidOperationException("Conversation participants unavailable.");
        var next=new ConversationSession(++nextConversation,initiator,target,declaration);
        conversationDeclaration=declaration.Clone();
        foreach(var actor in new[]{initiator,target})
        {
            conversationLocks.Add(actor);
            Scheduler.Hold(actor,true);
        }
        // The target may finish its current movement while the initiator follows.
        // Its action is physically held only after the host confirms alignment.
        conversationHolds.Add(initiator,Clock.Now);
        conversation=next;
        return next.View;
    }
    public bool AlignConversation(long id)
    {
        if(conversation is not { } current || current.Id!=id || !current.Aligned(Clock.Now))return false;
        conversationHolds.Add(current.Target,Clock.Now);
        return true;
    }
    public bool AdvanceConversation(long id,int line)
    {
        if(conversation is not { } current || current.Id!=id)return false;
        var before=current.View;
        if(!current.Advance(line,Clock.Now))return false;
        var authored=conversationDeclaration.Get("lines").Items().ElementAt(line);
        foreach(var share in authored.Get("shares").Items())
        {
            var sender=before.Line!.Speaker;
            var receiver=sender==current.Initiator?current.Target:current.Initiator;
            var from=FieldKey.Read(share.Get("from"),sender);
            var to=FieldKey.Read(share.Get("to"),receiver);
            if(actors[sender].Recall(from) is not {Known:true,Conflicted:false} fact)continue;
            var sourceIds=actors[sender].Evidence.Where(item=>item.Key==from).Select(item=>item.Id).Distinct().ToArray();
            actors[receiver].ReceiveDirected(new Observation("dialogue/"+ ++nextEvidence,to,fact.Value,fact.Confidence,ContentTime,
                InformationOrigin.Communication,JsonSerializer.SerializeToElement(new {conversation=id,line,sender,from,sourceIds})));
        }
        return true;
    }
    public bool InterruptConversation(long id)
    {
        if(conversation is not { } current || current.Id!=id || !current.Interrupt())return false;
        return true;
    }
    public bool CompleteConversation(long id)
    {
        if(conversation is not { } current || current.Id!=id || current.Phase is not ("finished" or "interrupted"))return false;
        ReleaseConversation();return true;
    }
    private void ReleaseConversation()
    {
        foreach(var (actor,heldAt) in conversationHolds)
        {
            if(running.TryGetValue(actor,out var execution))
            {
                var duration=Clock.Now-heldAt;
                if(execution.WorkStartedAt.HasValue)execution.WorkStartedAt+=duration;
                if(double.IsFinite(execution.DueAt))execution.DueAt+=duration;
                if(execution.CompletionDeferred)
                {
                    execution.CompletionDeferred=false;
                    completions.Enqueue(execution,Math.Max(Clock.Now,execution.DueAt));
                }
            }
        }
        foreach(var actor in conversationLocks)
        {
            Scheduler.Hold(actor,false);
            if(!actors[actor].IsObserving && !actors[actor].IsUpdating && actors[actor].PendingInformation>0)
                actors[actor].BeginRefresh(RefreshCause.Deliberate);
        }
        conversationLocks.Clear();
        conversationHolds.Clear();conversation=null;
    }

    public RuntimeSession(JsonElement world, JsonElement sessionPolicy, JsonElement scheduling,
        JsonElement clockPolicy, JsonElement residency, double initialTime)
    {
        World.Initialize(world.Get("objects"));
        inferenceBudget = sessionPolicy.Get("inference_rules_per_slice").GetInt32();
        workBudget = scheduling.Get("evaluations_per_slice").GetInt32();
        sliceMilliseconds = scheduling.Get("milliseconds_per_slice").Number(double.NaN);
        contentTimeUnit = sessionPolicy.Get("content_time_unit_seconds").Number(1);
        if (!double.IsFinite(contentTimeUnit) || contentTimeUnit <= 0) throw new InvalidDataException("Invalid content time unit.");
        if (inferenceBudget < 1 || workBudget < 1) throw new InvalidDataException("Positive session work budget required.");
        Scheduler = new(scheduling,PositionEligible,(_,action)=>TimeEligible(action));
        Clock = new(clockPolicy, initialTime);
        Rooms = new(residency);
        Rules = new(World, contentTimeUnit);
        observationKinds = sessionPolicy.Get("observation_kinds").Items().Select(x => x.Text()).ToHashSet(StringComparer.Ordinal);
        if (sessionPolicy.Get("clock_ref").ValueKind == JsonValueKind.Object)
            clockField = FieldKey.Read(sessionPolicy.Get("clock_ref"), "world");
    }

    public ActorClient RegisterActor(JsonElement declaration, JsonElement attention, IEnumerable<ActionCandidate> candidates, bool autonomous = true)
    {
        var actor = new ActorClient(declaration, attention);
        if (actors.ContainsKey(actor.Id)) throw new InvalidDataException("Duplicate actor: " + actor.Id);
        Scheduler.Register(actor, candidates, Clock.Now, autonomous);
        actors.Add(actor.Id, actor);
        foreach(var sensor in declaration.Get("perceptions").Items())
            sensoryEvents.Add((actor.Id,sensor.Clone(),Condition.Compile(sensor.Get("condition"),World.Subject),Condition.Compile(sensor.Get("knowledge_condition"),actor.Id),sensor.Get("refs").Items().Select(r=>FieldKey.Read(r,World.Subject)).ToArray()));
        var placement=declaration.Get("placement");
        if(placement.ValueKind==JsonValueKind.Object)
        {
            var position=placement.Get("position").Items().Select(value=>value.Number(double.NaN)).ToArray();
            if(position.Length!=3)throw new InvalidDataException("Physical placement requires three coordinates.");
            ReportPlacement(actor.Id,position[0],position[1],position[2],placement.Get("yaw").Number(),placement.Get("room").Text());
        }
        actorOrder = actors.Keys.ToArray();
        return actor;
    }

    private bool PositionEligible(string actor,ActionCandidate action)
    {
        if(Clock.Now>=observationHorizon)return false;
        if(ContentTime<actors[actor].Declaration.Get("wake_at_game_minutes").Number())return false;
        foreach(var threshold in action.Declaration.Get("need_below").Fields())
            if(!Needs(actor).TryGetValue(threshold.Name,out var value)||value>=threshold.Value.Number())return false;
        foreach(var threshold in action.Declaration.Get("need_above").Fields())
            if(!Needs(actor).TryGetValue(threshold.Name,out var value)||value<=threshold.Value.Number())return false;
        if(Incapacitated(actor))return false;
        if(!KnowledgeEligible(action))return false;
        if(!MechanicEligible(actor,action))return false;
        if(strategyBindings.TryGetValue(action.Id,out var strategy) && strategy.LastAttemptRevision==actors[actor].KnowledgeRevision)return false;
        if(!TimeEligible(action))return false;
        var minimum=action.Declaration.Get("minimum_travel_distance_m");
        if(minimum.ValueKind==JsonValueKind.Undefined)return true;
        var distance=minimum.Number(double.NaN);
        var coordinates=action.Declaration.Get("motor").Get("target").Items().Select(value=>value.Number(double.NaN)).ToArray();
        if(!double.IsFinite(distance)||distance<=0||coordinates.Length!=3||coordinates.Any(value=>!double.IsFinite(value)))
            throw new InvalidDataException("Invalid minimum travel distance or target: "+action.Id);
        if(!placements.TryGetValue(actor,out var placement))return false;
        var x=placement.X-coordinates[0];var y=placement.Y-coordinates[1];var z=placement.Z-coordinates[2];
        return x*x+y*y+z*z>=distance*distance;
    }

    private bool TimeEligible(ActionCandidate action)
    {
        if(actionCooldowns.TryGetValue(action.Id,out var ready)&&ContentTime<ready)return false;
        var notBefore=action.Declaration.Get("not_before_game_minutes");
        if(notBefore.ValueKind!=JsonValueKind.Undefined && ContentTime<notBefore.Number(double.PositiveInfinity))return false;
        var notAfter=action.Declaration.Get("not_after_game_minutes");
        if(notAfter.ValueKind!=JsonValueKind.Undefined && ContentTime>notAfter.Number(double.NegativeInfinity))return false;
        return true;
    }

    private bool KnowledgeEligible(ActionCandidate action)
    {
        foreach(var guard in action.Declaration.Get("knowledge_guards").Items())
        {
            var id=guard.Get("actor").Text();
            if(!actors.TryGetValue(id,out var client))throw new InvalidDataException("Unknown knowledge guard actor: "+id);
            var key=FieldKey.Read(guard.Get("ref"),id);
            var known=client.View().Knowledge.TryGetValue(key,out var fact) && fact.Known && !fact.Conflicted && fact.Value.ValueKind==JsonValueKind.True;
            var mode=guard.Get("mode").Text();
            if(mode=="known_true" && !known || mode=="not_known_true" && known)return false;
            if(mode is not ("known_true" or "not_known_true"))throw new InvalidDataException("Invalid knowledge guard mode.");
        }
        return true;
    }

    public ClientView View(string actor) => actors[actor].View();
    public IReadOnlyList<Evidence> Evidence(string actor)=>actors[actor].Evidence;
    public object DecisionAudit(Decision decision)
    {
        var client=actors[decision.Actor];
        return new {actor=decision.Actor,action=decision.Action.Id,execution=decision.Execution,label=decision.Action.Declaration.Get("label").Text(),
            intent=decision.Intent,needs=Needs(decision.Actor),candidate_scores=decision.Options??[],goal_planning=Scheduler.GoalAudit(decision.Actor),failure_memory=Scheduler.FailureAudit(decision.Actor,Clock.Now),
            recognition=decision.Action.Recognition.Evaluate(client.Recall).ToString(),predicted_readiness=decision.Action.Gate.Evaluate(client.Recall).ToString(),
            knowledge_basis=decision.Action.Gate.Inputs.Concat(decision.Action.Recognition.Inputs).Distinct().Select(key=>new {key,fact=client.Recall(key),
                sources=client.Evidence.Where(item=>item.Key==key&&client.Recall(key) is {Known:true} fact&&Values.Same(item.Value,fact.Value)&&item.Time==fact.ObservedAt&&item.Confidence==fact.Confidence)
                    .Select(item=>new {id=item.Id,time=item.Time,method=item.Method,source=item.Source}).ToArray()}).ToArray()};
    }
    public int PendingInformation(string actor)=>actors[actor].PendingInformation;
    public int EvidenceCount(string actor)=>actors[actor].Evidence.Count;
    public void ConfigureBindings(JsonElement bindings) => perception = new(bindings);
    public void ConfigureHostPhysicalBindings(JsonElement bindings)
    {
        foreach(var binding in bindings.Items())hostPhysicalBindings.Add(FieldKey.Read(binding,"world"));
    }
    public void ReportPhysicalBoolean(FieldKey key,bool value)
    {
        if(!hostPhysicalBindings.Contains(key))throw new InvalidOperationException("Physical field is not host-bound.");
        var before=World.Read(key);
        if(before is {Known:true,Conflicted:false} && (before.Value.ValueKind is JsonValueKind.True or JsonValueKind.False) && before.Value.GetBoolean()==value)return;
        Rules.Changed(World.Apply(new Dictionary<FieldKey,Fact>{{key,new(JsonSerializer.SerializeToElement(value),true,false,1,ContentTime,0)}}));
    }
    public void ConfigureIncapacitation(string actor,JsonElement reference)
    {
        if(!actors.ContainsKey(actor) || incapacitation.ContainsKey(actor))
            throw new InvalidDataException("Invalid incapacitation actor: "+actor);
        var key=FieldKey.Read(reference,World.Subject);
        var value=World.Read(key);
        if(value is not {Known:true,Conflicted:false} || value.Value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new InvalidDataException("Incapacitation requires a declared objective boolean: "+actor);
        incapacitation.Add(actor,key);
    }
    public bool Incapacitated(string actor)=>incapacitation.TryGetValue(actor,out var key) &&
        World.Read(key) is {Known:true,Conflicted:false} value && value.Value.ValueKind==JsonValueKind.True;
    public void ConfigureReservations(JsonElement slots)
    {
        foreach(var slot in slots.Items())Reservations.Define(slot.Get("id").Text(),slot.Get("capacity").GetInt32());
    }
    public IReadOnlyDictionary<string,double> Needs(string actor)=>Scheduler.Needs(actor,Clock.Now);
    public object PlayerPaths(string actor)=>Scheduler.Paths(actor,Clock.Now);
    public DecisionIntent? ActiveIntent(string actor)=>running.TryGetValue(actor,out var execution)?execution.Decision.Intent:null;
    public IEnumerable<(string Actor,AffectEvent Event)> DrainAffectEvents()=>Scheduler.DrainAffectEvents();
    public object Affect(string actor)=>Scheduler.Affect(actor);
    public void SetAutonomy(string actor,bool enabled)=>Scheduler.SetAutonomy(actor,enabled);
    public DriveEvaluation EvaluateDrive(string actor,string action)=>Scheduler.EvaluateDrive(actor,action,Clock.Now);
    public void ReconfigureDrives(string actor,JsonElement policy)=>Scheduler.ReconfigureDrives(actor,policy,Clock.Now);
    public Decision Submit(string actor, string action)
    {
        var decision = Scheduler.Submit(actor, action, Clock.Now, enqueue: false);
        Execute(decision);
        return decision;
    }
    public bool Receive(string actor, Observation observation) => actors[actor].Receive(observation);
    // Called only after the host reports an actual local perception. Reception is
    // filtered and buffered; it does not itself update the actor's knowledge.
    public bool ReceivePhysicalObservation(string actor, FieldKey physical, string source)
    {
        var local=perception.Project(actor,physical);
        var fact=World.Read(physical);
        if(local is null || fact is not { Known:true, Conflicted:false } || perception.Project(actor,fact.Value) is not { } value)return false;
        return actors[actor].Receive(new Observation("perception/"+ ++nextEvidence,local.Value,value,fact.Confidence,ContentTime,
            InformationOrigin.Passive,JsonSerializer.SerializeToElement(new {actor,source})));
    }
    public string BeginObservation(string actor, IEnumerable<FieldKey> focus)
    {
        if (running.ContainsKey(actor) || conversationLocks.Contains(actor)) throw new InvalidOperationException("Actor is occupied.");
        return actors[actor].BeginObservation(focus);
    }
    public void EndObservation(string actor, string token) => actors[actor].EndObservation(token);
    public void Refresh(string actor, RefreshCause cause)
    {
        if (running.ContainsKey(actor) || conversationLocks.Contains(actor)) throw new InvalidOperationException("Actor is occupied.");
        actors[actor].BeginRefresh(cause);
    }

    private void Execute(Decision decision)
    {
        if(Incapacitated(decision.Actor))
        {
            var attempt=CaptureStartAttempt(decision);
            Scheduler.Cancel(decision,Clock.Now);
            PublishReceipt(decision,false,"actor_incapacitated",startAttempt:attempt);
            return;
        }
        try { StartExecution(decision); }
        catch
        {
            Reservations.Release(new(decision.Actor,decision.Execution));
            if(running.Remove(decision.Actor,out var execution))FinishObservation(execution);
            actors[decision.Actor].FocusAction([]);
            Scheduler.Cancel(decision,Clock.Now);
            throw;
        }
    }

    private void StartExecution(Decision decision)
    {
        if (!Scheduler.Owns(decision) || decision.StartedAt > Clock.Now || running.ContainsKey(decision.Actor)) throw new InvalidOperationException("Actor cannot start another action.");
        // Actor access and objective validation stay separate. Start conditions never
        // grant knowledge of an unobserved objective failure.
        var declaration = decision.Action.Declaration;
        var gate = declaration.Get("objective_gate").ValueKind == JsonValueKind.Object
            ? Condition.Compile(declaration.Get("objective_gate"), World.Subject) : new Condition.Constant(Truth.True);
        var effects = declaration.Get("effects").Items().Select(x => Effect.Compile(x, World.Subject)).ToArray();
        var postcondition = declaration.Get("objective_postcondition").ValueKind == JsonValueKind.Object
            ? Condition.Compile(declaration.Get("objective_postcondition"), World.Subject) : null;
        var execution = new Execution(decision, effects, gate, postcondition, declaration.Get("requires_host_completion").Flag());
        execution.WorkAfterArrival=execution.HostRequired&&declaration.Get("timing").Get("work_after_arrival").Flag();
        execution.HostElapsed=execution.HostRequired&&declaration.Get("timing").Get("host_elapsed").Flag();
        if(execution.WorkAfterArrival&&execution.HostElapsed)throw new InvalidDataException("An execution must select work timing or physical elapsed timing.");
        if(execution.WorkAfterArrival||execution.HostElapsed)execution.DueAt=double.PositiveInfinity;
        else execution.WorkStartedAt=decision.StartedAt;
        var resourceIds=declaration.Get("resource_reservations").Items().Select(item=>item.Text()).ToArray();
        if(!Reservations.TryAcquire(new(decision.Actor,decision.Execution),resourceIds))
        {
            var attempt=CaptureStartAttempt(decision);
            Scheduler.Cancel(decision,Clock.Now);
            PublishReceipt(decision,false,"standing_resource_busy",blockedResources:Reservations.Blocked(decision.Actor,resourceIds),startAttempt:attempt);
            return;
        }
        var focus = decision.Action.Gate.Inputs.Concat(decision.Action.Recognition.Inputs).Concat(declaration.Get("grants").Items()
            .Concat(declaration.Get("failure_grants").Items()).Select(x => perception.Project(decision.Actor, FieldKey.Read(x, decision.Actor)))
            .Where(x => x.HasValue).Select(x => x!.Value)).ToArray();
        if(declaration.Get("kind").Text()=="deduce" && deductions.TryGetValue(decision.Action.Id,out var configuredDeduction))
            focus=focus.Concat(configuredDeduction.declaration.Get("results").Items().Select(item=>FieldKey.Read(item.Get("ref"),decision.Actor))).ToArray();
        if(strategyBindings.TryGetValue(decision.Action.Id,out var configuredStrategy))
        {
            focus=focus.Append(configuredStrategy.Output).ToArray();
            if(configuredStrategy.Completion is { } completion)focus=focus.Append(completion).ToArray();
        }
        focus=focus.Concat(MechanicFocus(decision.Action)).Distinct().ToArray();
        actors[decision.Actor].FocusAction(focus);
        if (observationKinds.Contains(declaration.Get("kind").Text()))
            execution.ObservationToken = actors[decision.Actor].BeginObservation(focus);
        running.Add(decision.Actor, execution);
        var spatial=BeginSpatialNavigation(execution);
        if(!execution.WorkAfterArrival&&!spatial&&strategyBindings.TryGetValue(decision.Action.Id,out var immediateStrategy))
            immediateStrategy.Activity.Begin(Clock.Now,decision.Action.Duration/contentTimeUnit);
        if (!execution.HostRequired&&!spatial) completions.Enqueue(execution, execution.DueAt);
        dispatched.Enqueue(decision);
    }

    public bool BeginWork(Decision decision)
    {
        if(conversationHolds.ContainsKey(decision.Actor)||!Current(decision,out var execution)||execution!.CancelRequested||!execution.WorkAfterArrival||execution.WorkStartedAt.HasValue)return false;
        execution.WorkStartedAt=Clock.Now;
        execution.DueAt=Clock.Now+decision.Action.Duration;
        if(strategyBindings.TryGetValue(decision.Action.Id,out var strategy))
        {
            if(strategy.Actor!=decision.Actor)throw new InvalidDataException("Timed strategy actor mismatch.");
            strategy.Activity.Begin(Clock.Now,decision.Action.Duration/contentTimeUnit);
        }
        return true;
    }

    private bool Current(Decision decision,out Execution? execution)=>running.TryGetValue(decision.Actor,out execution)&&ReferenceEquals(execution.Decision,decision);

    public bool HostCompleted(Decision decision)
    {
        if(conversationHolds.ContainsKey(decision.Actor)||!Current(decision,out var execution)||execution!.CancelRequested||execution.WorkAfterArrival&&!execution.WorkStartedAt.HasValue)return false;
        if (execution.HostCompleted) return true;
        if(execution.HostElapsed)execution.DueAt=Clock.Now;
        execution.HostCompleted = true;
        if (execution.HostRequired) completions.Enqueue(execution, Math.Max(Clock.Now, execution.DueAt));
        return true;
    }

    public ActivityView? Activity(string actor)
    {
        if(!running.TryGetValue(actor,out var execution))return null;
        if(spatialNavigation.TryGetValue(execution.Decision.Execution,out var navigation))
            return new(actor,execution.Decision.Action.Id,execution.Decision.Execution,execution.CancelRequested?"cancelling":navigation.Phase,
                execution.WorkStartedAt,double.IsFinite(execution.DueAt)?execution.DueAt:null,false);
        return new(actor,execution.Decision.Action.Id,execution.Decision.Execution,
            execution.CancelRequested?"cancelling":execution.WorkAfterArrival?execution.WorkStartedAt.HasValue?"working":"preparing":execution.HostElapsed?"moving":"working",
            execution.WorkStartedAt,double.IsFinite(execution.DueAt)?execution.DueAt:null,execution.HostCompleted);
    }

    public bool WorkElapsed(Decision decision)
    {
        if(conversationHolds.ContainsKey(decision.Actor)||!Current(decision,out var execution)||!execution!.WorkStartedAt.HasValue||Clock.Now<execution.DueAt)return false;
        if(!strategyBindings.TryGetValue(decision.Action.Id,out var strategy))return true;
        if(completedStrategies.ContainsKey(decision.Execution))return true;
        var choices=strategy.Activity.Finish(Clock.Now);
        if(choices is null)return false;
        completedStrategies[decision.Execution]=(actors[decision.Actor].KnowledgeRevision,choices);
        return true;
    }
    public bool PhysicalActionPermitted(Decision decision)=>Current(decision,out var execution)&&!execution!.CancelRequested && TimeEligible(decision.Action) && KnowledgeEligible(decision.Action) && execution.CompletionGate.Evaluate(World.Read)==Truth.True;
    public bool Working(string actor)=>!conversationHolds.ContainsKey(actor)&&running.TryGetValue(actor,out var execution)&&!execution.CancelRequested&&execution.WorkStartedAt.HasValue&&
        (execution.WorkAfterArrival||spatialNavigation.TryGetValue(execution.Decision.Execution,out var nav)&&nav.Phase=="working");

    public bool RequestCancel(string actor)
    {
        if(conversationLocks.Contains(actor) && conversation is { } active)
        {
            InterruptConversation(active.Id);
            CompleteConversation(active.Id);
        }
        if(!running.TryGetValue(actor,out var execution))return false;
        if(execution.CancelRequested)return true;
        execution.CancelRequested=true;
        if(!execution.HostRequired||!execution.Dispatched)return ConfirmCancelled(execution.Decision);
        cancellations.Enqueue(execution.Decision);
        return true;
    }

    public bool ConfirmCancelled(Decision decision,bool retainOccupiedResources=false)
    {
        if(!Current(decision,out var execution)||!execution!.CancelRequested)return false;
        FinishObservation(execution);
        journeys.Remove(decision.Execution);
        spatialNavigation.Remove(decision.Execution);
        if(strategyBindings.TryGetValue(decision.Action.Id,out var strategy))strategy.Activity.Cancel();
        completedStrategies.Remove(decision.Execution);
        deductionSelections.Remove(decision.Execution);
        actors[decision.Actor].FocusAction([]);
        ReleaseResources(execution,retainOccupiedResources);
        Scheduler.Cancel(decision,Clock.Now);running.Remove(decision.Actor);
        PublishReceipt(decision,false,"cancelled");
        return true;
    }

    public bool HostFailed(Decision decision,string reason)
    {
        if(!Current(decision,out var execution))return false;
        if(execution!.CancelRequested)return ConfirmCancelled(decision);
        // A rejected arrival is an attempted action. Report its real boundary
        // failure instead of treating it as a voluntary player cancellation.
        // Actual path/geometry failures retain their original host reason.
        if(reason is "arrival_rejected" or "target_not_present")
        {
            if(!TimeEligible(decision.Action))reason="action_time_window_closed";
            else if(!KnowledgeEligible(decision.Action))reason="action_knowledge_changed";
            else if(execution.CompletionGate.Evaluate(World.Read)!=Truth.True)reason="objective_condition_failed";
        }
        var wasObserving=execution.ObservationToken is not null;
        journeys.Remove(decision.Execution);
        spatialNavigation.Remove(decision.Execution);
        if(strategyBindings.TryGetValue(decision.Action.Id,out var strategy))strategy.Activity.Cancel();
        completedStrategies.Remove(decision.Execution);
        deductionSelections.Remove(decision.Execution);
        FinishObservation(execution);
        Reservations.Release(new(decision.Actor,decision.Execution));
        Scheduler.Cancel(decision,Clock.Now);running.Remove(decision.Actor);
        if(!wasObserving)actors[decision.Actor].BeginRefresh(RefreshCause.FailedAction);
        actors[decision.Actor].FocusAction([]);
        PublishReceipt(decision,false,reason);
        return true;
    }

    private void FinishObservation(Execution execution)
    {
        if(execution.ObservationToken is not { } token)return;
        actors[execution.Decision.Actor].EndObservation(token);execution.ObservationToken=null;
    }

    private void ReleaseResources(Execution execution,bool retain)
    {
        var owner=new ReservationOwner(execution.Decision.Actor,execution.Decision.Execution);
        if(retain&&execution.Decision.Action.Declaration.Get("retain_occupied_resources").Flag())Reservations.Retain(owner);
        else Reservations.Release(owner);
    }

    public void VacatedRetainedResources(string actor)=>Reservations.Release(new(actor,0));

    public bool TryReceipt(out ActionReceipt? receipt) => receipts.TryDequeue(out receipt);
    public bool TryActionOutcome(out ActionOutcome? outcome)=>actionOutcomes.TryDequeue(out outcome);
    private ActionStartAttempt CaptureStartAttempt(Decision decision)=>new(decision.Options??[],EvaluateDrive(decision.Actor,decision.Action.Id),
        JsonSerializer.SerializeToElement(DecisionAudit(decision)));
    private void PublishReceipt(Decision decision,bool success,string reason,IEnumerable<FieldChange>? changes=null,IReadOnlyDictionary<string,double>? needsBefore=null,
        ActionInterruption? interruption=null,SavedFact[]? interruptionBasis=null,string[]? blockedResources=null,ActionStartAttempt? startAttempt=null)
    {
        var client=actors[decision.Actor];
        IEnumerable<FieldKey> Blockers(Condition condition)
        {
            if(condition is Condition.All all)return all.Items.Where(item=>item.Evaluate(World.Read)!=Truth.True).SelectMany(Blockers);
            return condition.Inputs;
        }
        var objective=decision.Action.Declaration.Get("objective_gate");
        var keys=objective.ValueKind==JsonValueKind.Object?Blockers(Condition.Compile(objective,World.Subject)).Where(key=>client.Recall(key) is {Known:true}):[];
        keys=keys.Concat(decision.Action.Declaration.Get("failure_grants").Items().Select(value=>FieldKey.Read(value,decision.Actor)));
        if(reason=="standing_resource_busy")keys=[];
        else if(!keys.Any())keys=decision.Action.Gate.Inputs;
        var learned=Scheduler.RecordOutcome(decision,success,reason,keys,Clock.Now,blockedResources);
        var narrative=success?CompleteNarrative(decision):Array.Empty<ActionNarrative>();
        receipts.Enqueue(new(decision.Actor,decision.Action.Id,Clock.Now,success,reason,decision.Execution,decision.Intent,interruption,narrative));
        var needs=Needs(decision.Actor);
        actionOutcomes.Enqueue(new(decision.Actor,decision.Action.Id,decision.Execution,decision.StartedAt,Clock.Now,success,reason,
            decision.Intent,changes?.ToArray()??[],new(needsBefore??needs,StringComparer.Ordinal),new(needs,StringComparer.Ordinal),interruption,interruptionBasis,narrative,learned,startAttempt));
    }
    public bool Available(string actor,string action)
    {
        return Scheduler.Available(actor,action);
    }
    public ActionCandidate Candidate(string actor,string action)=>Scheduler.Candidate(actor,action);
    public bool TryAction(out Decision? decision)
    {
        var count=dispatched.Count;
        while(count-->0 && dispatched.TryDequeue(out decision))
            if(Current(decision,out var execution)&&!execution!.CancelRequested)
            {
                if(conversationHolds.ContainsKey(decision.Actor)){dispatched.Enqueue(decision);continue;}
                execution.Dispatched=true;return true;
            }
        decision=null;return false;
    }
    public bool TryCancellation(out Decision? decision)
    {
        while(cancellations.TryDequeue(out decision))if(Current(decision,out var execution)&&execution!.CancelRequested)return true;
        decision=null;return false;
    }

    public void Step(double realSeconds, bool idle, bool paused, string? playerActor = null)
    {
        // Only an explicit simulation pause suspends the session. Opening UI or
        // displaying a spoken line does not request a simulation pause.
        if (paused) return;
        AdvanceSpatialNavigation();
        AdvanceMechanics();
        foreach(var sensor in sensoryEvents)
        {
            if(ContentTime<sensor.Data.Get("not_before_game_minutes").Number())continue;
            var client=actors[sensor.Actor];var id="perception/"+sensor.Data.Get("id").Text();
            var during=sensor.Data.Get("during_action").Text();
            if(during.Length>0&&!running.Values.Any(e=>e.Decision.Action.Id==during&&!e.CancelRequested))continue;
            var repeating=sensor.Data.Get("repeat_on_change").Flag();
            if(client.IsUpdating||!repeating&&client.Evidence.Any(e=>e.Id==id)||sensor.WorldGate.Evaluate(World.Read)!=Truth.True||sensor.KnowledgeGate.Evaluate(client.Recall)!=Truth.True)continue;
            foreach(var field in sensor.Fields)
            {
                var local=perception.Project(sensor.Actor,field);var fact=World.Read(field);
                if(local is null||fact is not {Known:true,Conflicted:false})continue;
                var sampleId=repeating?id+"/revision/"+fact.Revision:id;
                if(repeating&&client.Evidence.Any(item=>item.Id==sampleId&&item.Key==local.Value))continue;
                client.ReceiveSalient(new Observation(sampleId,local.Value,fact.Value,fact.Confidence,ContentTime,InformationOrigin.Passive,
                    JsonSerializer.SerializeToElement(new {actor=sensor.Actor,sensor=sensor.Data.Get("id").Text(),channel=sensor.Data.Get("channel").Text("sight"),label=sensor.Data.Get("label").Text(),physical_field=field,world_revision=fact.Revision})));
            }
        }
        Rules.Wake(Clock.Now);
        Rules.Step(ContentTime, workBudget, sliceMilliseconds);
        foreach(var actor in incapacitation.Keys)
            if(Incapacitated(actor) && (running.ContainsKey(actor) || conversationLocks.Contains(actor)))RequestCancel(actor);
        for (var n = 0; n < Math.Min(actorOrder.Length, workBudget); n++)
        {
            var actor = actors[actorOrder[actorCursor]];
            actorCursor = (actorCursor + 1) % actorOrder.Length;
            if (actor.IsUpdating) actor.ContinueRefresh(inferenceBudget);
            if(!running.ContainsKey(actor.Id) && !conversationLocks.Contains(actor.Id))actor.ProcessDirectedMessages();
        }
        if(strategyBindings.Count>0)
        {
            var entry=strategyBindings.ElementAt(strategyCursor++%strategyBindings.Count);
            if(entry.Value.Activity.Active && !conversationHolds.ContainsKey(entry.Value.Actor))
                entry.Value.Activity.Step(inferenceBudget,TimeSpan.FromMilliseconds(sliceMilliseconds));
        }
        var processed = 0;
        while (processed < workBudget && completions.TryPeek(out var execution, out var due))
        {
            if(!Current(execution.Decision,out var active)||!ReferenceEquals(active,execution)||execution.CancelRequested)
            {processed++;completions.Dequeue();continue;}
            if(conversationHolds.ContainsKey(execution.Decision.Actor))
            {processed++;completions.Dequeue();execution.CompletionDeferred=true;continue;}
            if(due<execution.DueAt)
            {processed++;completions.Dequeue();completions.Enqueue(execution,execution.DueAt);continue;}
            if(due>Clock.Now)break;
            if(strategyBindings.ContainsKey(execution.Decision.Action.Id)&&!WorkElapsed(execution.Decision))break;
            processed++;
            Commit(execution);
            completions.Dequeue();
        }
        // Drain decisions retained by an older checkpoint before admitting new work.
        if(Clock.Now<observationHorizon)
        {
            for (var n = 0; n < workBudget && Scheduler.TryTake(out var decision); n++) Execute(decision!);
            HasPendingDecisionWork=Scheduler.Step(Clock.Now,Execute).Pending;
        }
        else HasPendingDecisionWork=false;
        var next = completions.TryPeek(out _, out var nextDue) ? nextDue : double.PositiveInfinity;
        next = Math.Min(next, Rules.NextTime);
        next = Math.Min(next,NextMechanicTime());
        next = Math.Min(next,NextSpatialTime());
        next = Math.Min(next,Scheduler.NextDecisionTime);
        next = Math.Min(next,observationHorizon);
        // A decision is evaluated in bounded CPU slices. Those slices belong to
        // the same simulation instant: spending a renderer frame on candidate
        // scoring must not add poison exposure or delay a rescue in world time.
        // Even a decision with no eligible action completes its finite selection
        // and schedules the next poll, so an idle actor cannot hold time forever.
        var pending = Rules.Pending || HasPendingDecisionWork || next <= Clock.Now;
        var priorTime=Clock.Now;
        Clock.Step(realSeconds, idle, paused, pending, Math.Max(Clock.Now, next),playerActor is { } actorId&&Working(actorId),physicalClockInput||HasHostNavigation);
        var elapsed=Clock.Now-priorTime;
        ElapseSpatialNavigation(elapsed);
        if(elapsed>0 && accumulators.Count>0)
        {
            var writes=new Dictionary<FieldKey,Fact>();
            foreach(var item in accumulators)
            {
                var active=World.Read(item.Active);var present=World.Read(item.Present);var amount=World.Read(item.Amount);
                if(active is not {Known:true,Conflicted:false} || active.Value.ValueKind!=JsonValueKind.True ||
                   present is not {Known:true,Conflicted:false} || present.Value.ValueKind!=JsonValueKind.True ||
                   amount is not {Known:true,Conflicted:false})continue;
                writes[item.Amount]=new(JsonSerializer.SerializeToElement(amount.Value.Number()+elapsed*item.Rate),true,false,1,ContentTime,0);
            }
            if(writes.Count>0)Rules.Changed(World.Apply(writes));
        }
        if (clockField is { } key)
            Rules.Changed(World.Apply(new Dictionary<FieldKey, Fact>
            { [key] = new(JsonSerializer.SerializeToElement(ContentTime), true, false, 1, ContentTime, 0) }));
    }

    private void Commit(Execution execution)
    {
        var decision = execution.Decision;
        if (!Scheduler.Owns(decision) || Clock.Now < execution.DueAt) throw new InvalidOperationException("Invalid action commit.");
        var objectiveTruth=execution.CompletionGate.Evaluate(World.Read);
        var timeEligible=TimeEligible(decision.Action);var knowledgeEligible=KnowledgeEligible(decision.Action);
        var success = objectiveTruth==Truth.True&&timeEligible&&knowledgeEligible;
        var failureReason=objectiveTruth!=Truth.True?"objective_condition_failed":!timeEligible?"action_time_window_closed":!knowledgeEligible?"action_knowledge_changed":"action_postcondition_failed";
        var writes = new Dictionary<FieldKey, Fact>();
        var changes=new List<FieldChange>();
        Fact? Read(FieldKey key) => success ? writes.GetValueOrDefault(key) ?? World.Read(key) : World.Read(key);
        if (success)
        {
            try
            {
                foreach (var effect in execution.Effects) writes[effect.Key] = effect.Resolve(Read, ContentTime);
                if (execution.Postcondition is { } post && post.Evaluate(Read) != Truth.True) success = false;
            }
            catch (InvalidOperationException) { success = false;failureReason="action_effect_failed"; }
        }
        var client = actors[decision.Actor];
        if(strategyBindings.ContainsKey(decision.Action.Id) && (!completedStrategies.TryGetValue(decision.Execution,out var strategyResult) || strategyResult.Revision!=client.KnowledgeRevision))
        {success=false;failureReason="strategy_basis_changed";}
        var feedback = new List<Observation>();
        if(success && strategyBindings.TryGetValue(decision.Action.Id,out var binding) && completedStrategies.TryGetValue(decision.Execution,out var result))
        {
            var best=result.Choices.Where(choice=>choice.Ready).OrderByDescending(choice=>choice.Utility).FirstOrDefault();
            binding.LastAttemptRevision=result.Revision;
            LastStrategy=new {actor=decision.Actor,action=decision.Action.Id,knowledge_revision=result.Revision,choices=result.Choices,selected=best?.Action};
            RecordMechanic(decision,"strategy",best is not null,LastStrategy);
            if(best is not null)
            {
                feedback.Add(new Observation("strategy/"+(++nextEvidence),binding.Output,JsonSerializer.SerializeToElement(best.Action),1,ContentTime,InformationOrigin.ActionFeedback,
                    JsonSerializer.SerializeToElement(new {actor=decision.Actor,action=decision.Action.Id,knowledge_revision=result.Revision,utility=best.Utility,theory_hash=best.TheoryHash,evidence=best.EvidenceNodes})));
                if(binding.Completion is { } completed)
                    feedback.Add(new Observation("strategy/"+(++nextEvidence),completed,JsonSerializer.SerializeToElement(true),1,ContentTime,InformationOrigin.ActionFeedback,
                        JsonSerializer.SerializeToElement(new {actor=decision.Actor,action=decision.Action.Id,knowledge_revision=result.Revision})));
                if(binding.Publish)writes[binding.Output]=new(JsonSerializer.SerializeToElement(best.Action),true,false,1,ContentTime,0);
            }
            else {success=false;failureReason="strategy_no_feasible_option";}
        }
        if(success&&inlineDeductions.ContainsKey(decision.Action.Id))
        {success=EvaluateInlineDeduction(decision,feedback);if(!success)failureReason="deduction_unproved";}
        else if(success && decision.Action.Declaration.Get("kind").Text()=="deduce")
        {
            feedback.AddRange(EvaluateDeduction(client,decision,out var proved));
            if(!proved){success=false;failureReason="deduction_unproved";feedback.Clear();}
        }
        if(success&&decision.Action.Declaration.Get("suggestion").ValueKind==JsonValueKind.Object)
        {success=EvaluateSuggestion(decision,writes,feedback,changes);if(!success)failureReason="suggestion_rejected";}
        if(success&&decision.Action.Declaration.Get("incantation").ValueKind==JsonValueKind.Object)
        {success=EvaluateIncantation(decision,writes,feedback);if(!success)failureReason="incantation_precondition_failed";}
        var grants = decision.Action.Declaration.Get(success ? "grants" : "failure_grants");
        foreach (var grant in grants.Items())
        {
            var key = FieldKey.Read(grant, decision.Actor);
            var target = perception.Project(decision.Actor, key);
            if (target is null || Read(key) is not { Known: true, Conflicted: false } fact || perception.Project(decision.Actor, fact.Value) is not { } value) continue;
            var origin = !success ? InformationOrigin.ActionFailure : execution.ObservationToken is not null
                ? InformationOrigin.DeliberateObservation : InformationOrigin.ActionFeedback;
            var sample = new Observation("action/" + ++nextEvidence, target.Value, value, fact.Confidence, ContentTime, origin,
                JsonSerializer.SerializeToElement(new { actor = decision.Actor, action = decision.Action.Id,execution=decision.Execution,physical_field=key,
                    world_revision=success&&writes.ContainsKey(key)?(long?)null:fact.Revision }));
            if (execution.ObservationToken is not null || !success) client.Receive(sample);
            else feedback.Add(sample);
        }
        if (execution.ObservationToken is { } token)
        {foreach(var sample in feedback)client.Receive(sample);client.EndObservation(token);}
        else if (success||feedback.Count>0) client.BeginActionFeedback(feedback);
        else client.BeginRefresh(RefreshCause.FailedAction);
        if (success)
        {
            var committedChanges=World.Apply(writes);changes.AddRange(committedChanges);Rules.Changed(committedChanges);
            var handoffs=decision.Action.Declaration.Get("handoffs").Items().ToList();
            if(decision.Action.Declaration.Get("handoff").ValueKind==JsonValueKind.Object)handoffs.Add(decision.Action.Declaration.Get("handoff"));
            foreach(var handoff in handoffs)
            {
                if(handoff.Get("only_if").ValueKind==JsonValueKind.Object && Condition.Compile(handoff.Get("only_if"),World.Subject).Evaluate(World.Read)!=Truth.True)continue;
                var recipient=actors[handoff.Get("actor").Text()];
                foreach(var reference in handoff.Get("refs").Items().Concat(handoff.Get("result_refs").Items()))
                {
                    var key=FieldKey.Read(reference,decision.Actor);
                    var isResult=handoff.Get("result_refs").Items().Any(item=>FieldKey.Read(item,decision.Actor)==key);
                    var fresh=feedback.LastOrDefault(item=>item.Key==key);
                    var fact=isResult ? writes.GetValueOrDefault(key) : fresh is not null?new Fact(fresh.Value,true,false,fresh.Confidence,fresh.Time,0):client.Recall(key);
                    if(fact is not {Known:true,Conflicted:false})continue;
                    var sourceIds=client.Evidence.Where(item=>item.Key==key).Select(item=>item.Id).Concat(feedback.Where(item=>item.Key==key).Select(item=>item.Id)).Distinct().ToArray();
                    recipient.ReceiveDirected(new Observation("handoff/"+(++nextEvidence),key,fact.Value,fact.Confidence,ContentTime,
                        InformationOrigin.Communication,JsonSerializer.SerializeToElement(new {actor=decision.Actor,recipient=recipient.Id,action=decision.Action.Id,execution=decision.Execution,sourceIds,isResult})));
                }
                if(!running.ContainsKey(recipient.Id) && !recipient.IsObserving && !recipient.IsUpdating && recipient.PendingInformation>0)
                    recipient.BeginRefresh(RefreshCause.Deliberate);
            }
        }
        if(success)foreach(var broadcast in decision.Action.Declaration.Get("broadcast_observations").Items())
            {
                if(broadcast.Get("only_if").ValueKind==JsonValueKind.Object && Condition.Compile(broadcast.Get("only_if"),World.Subject).Evaluate(World.Read)!=Truth.True)continue;
                var recipient=actors[broadcast.Get("actor").Text()];
                foreach(var reference in broadcast.Get("refs").Items())
                {
                    var key=FieldKey.Read(reference,decision.Actor);
                    if(!grants.Items().Any(grant=>FieldKey.Read(grant,decision.Actor)==key))continue;
                    if(Read(key) is not {Known:true,Conflicted:false} fact)continue;
                    recipient.ReceiveDirected(new Observation("report/"+(++nextEvidence),key,fact.Value,fact.Confidence,ContentTime,
                        InformationOrigin.Communication,JsonSerializer.SerializeToElement(new {actor=decision.Actor,action=decision.Action.Id,execution=decision.Execution,recipient=recipient.Id,physical_field=key,world_revision=World.Read(key)?.Revision})));
                }
                if(!running.ContainsKey(recipient.Id) && !recipient.IsObserving && !recipient.IsUpdating && recipient.PendingInformation>0)
                    recipient.BeginRefresh(RefreshCause.Deliberate);
            }
        client.FocusAction([]);
        var needsBefore=Needs(decision.Actor);
        Scheduler.Complete(decision, Clock.Now, success,execution.HostElapsed||spatialNavigation.TryGetValue(decision.Execution,out var nav)&&nav.PureMovement);
        if(success&&decision.Action.Declaration.Get("cooldown_minutes").Number()>0)
            actionCooldowns[decision.Action.Id]=ContentTime+decision.Action.Declaration.Get("cooldown_minutes").Number();
        journeys.Remove(decision.Execution);
        spatialNavigation.Remove(decision.Execution);
        ReleaseResources(execution,success&&decision.Action.Declaration.Get("retain_occupied_resources").Flag());
        running.Remove(decision.Actor);
        if(success && decision.Action.Declaration.Get("rest_until_game_minutes").ValueKind==JsonValueKind.Number)
            Clock.RestUntil(decision.Action.Declaration.Get("rest_until_game_minutes").Number()*60);
        completedStrategies.Remove(decision.Execution);
        deductionSelections.Remove(decision.Execution);
        ActionInterruption? interruption=null;SavedFact[]? interruptionBasis=null;
        var opportunity=decision.Action.Declaration.Get("interruptible_opportunity");
        if(!success&&objectiveTruth==Truth.False&&timeEligible&&knowledgeEligible&&failureReason=="objective_condition_failed"&&changes.Count==0&&opportunity.ValueKind==JsonValueKind.Object)
        {
            var lost=Condition.Compile(opportunity.Get("lost_when"),World.Subject);var inputs=lost.Inputs.Distinct().ToArray();
            if(inputs.All(key=>World.Read(key) is {Known:true,Conflicted:false})&&lost.Evaluate(World.Read)==Truth.True)
            {
                interruption=new(opportunity.Get("reason").Text(),opportunity.Get("label").Text());
                interruptionBasis=inputs.Select(key=>new SavedFact(key,World.Read(key)!)).ToArray();
            }
        }
        PublishReceipt(decision,success,success?"completed":failureReason,changes,needsBefore,interruption,interruptionBasis);
    }

    private IEnumerable<Observation> EvaluateDeduction(ActorClient client,Decision decision,out bool proved)
    {
        if(!deductions.TryGetValue(decision.Action.Id,out var configured))throw new InvalidOperationException("No deduction theory configured for action.");
        var authored=configured.theory;
        var deductionDeclaration=configured.declaration;
        var scope=deductionDeclaration.Get("scope").Text();
        var original=authored.Scopes[scope];
        var evidence=new List<CaseAxiom>();
        foreach(var mapping in deductionDeclaration.Get("evidence").Items())
        {
            if(Condition.Compile(mapping.Get("when"),client.Id).Evaluate(client.Recall)!=Truth.True)continue;
            var name=mapping.Get("assumption").Text();
            var assumption=original.Axioms.Single(item=>item.Id==name);
            var sources=client.Evidence.Where(item=>Condition.Compile(mapping.Get("when"),client.Id).Inputs.Contains(item.Key)).Select(item=>item.Id).Distinct().ToArray();
            evidence.Add(new("observed/"+name,assumption.Literal,JsonSerializer.Serialize(new {actor=client.Id,sources})));
        }
        var grounded=authored.WithoutAssumptions(scope).WithEvidence(scope,evidence);
        var observations=new List<Observation>();
        var results=new List<object>();
        proved=true;
        foreach(var mapping in deductionDeclaration.Get("results").Items())
        {
            var query=mapping.Get("query").Text();
            var goal=original.Theorems.Single(item=>item.Id==query);
            var result=grounded.Prove(scope,goal.Conclusion);
            proved&=result.Status=="proved";
            results.Add(new {query,label=mapping.Get("label").Text(),unknown_label=mapping.Get("unknown_label").Text(),result.Status,result.Support,result.Refutation});
            if(result.Status!="proved")continue;
            observations.Add(new("proof/"+ ++nextEvidence,FieldKey.Read(mapping.Get("ref"),client.Id),
                JsonSerializer.SerializeToElement(true),1,ContentTime,InformationOrigin.ActionFeedback,
                JsonSerializer.SerializeToElement(new {actor=client.Id,action=decision.Action.Id,query,result.Support})));
        }
        LastDeduction=new {actor=client.Id,scope,knowledge_revision=client.KnowledgeRevision,evidence=evidence.ToArray(),results=results.ToArray()};
        RecordMechanic(decision,"deduction",proved,LastDeduction);
        return observations;
    }
}
