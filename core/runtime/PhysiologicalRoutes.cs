using System.Text.Json;

namespace DuelView.Runtime;

public sealed record PhysiologicalStepReceipt(string Action,long Execution,double Time,double NeedValue);
public sealed record PhysiologicalRouteCheckpoint(string Route,int Index,string? InterruptedTask,double StartedAt,double NeedBefore,
    double? RecoveredAt,PhysiologicalStepReceipt[] Steps);
public sealed record PhysiologicalRouteReceipt(string Route,string Need,string? Task,double StartedAt,double? RecoveredAt,double FinishedAt,
    double NeedBefore,double NeedAfter,string Outcome,PhysiologicalStepReceipt[] Steps);
public sealed record PhysiologicalRoutesState(PhysiologicalRouteCheckpoint? Current,PhysiologicalRouteReceipt[] Recent);

/// <summary>Finite, knowledge-admitted journeys to an authored recovery action.
/// Navigation and recovery use normal actions and real completion receipts.
/// The route remains active through its return leg after the need recovers.</summary>
internal sealed class PhysiologicalRoutes
{
    private sealed record Route(string Id,string Label,string Need,Condition Available,ActionCandidate[] Actions,int RecoveryIndex,double EstimatedCost);
    private readonly ActorClient actor;
    private readonly DriveCalculator needs;
    private readonly Dictionary<string,double> recoveryThreshold;
    private readonly Dictionary<string,Route> routes=new(StringComparer.Ordinal);
    private readonly double timeUnit;
    private PhysiologicalRouteCheckpoint? current;
    private readonly List<PhysiologicalRouteReceipt> recent=[];
    internal bool Active=>current is not null;
    internal string? Need=>current is { } c?routes[c.Route].Need:null;
    internal string? ActiveId=>current?.Route;
    internal string? StepId=>current is { } c?routes[c.Route].Actions[c.Index].Id:null;

    internal PhysiologicalRoutes(ActorClient actor,ActionCandidate[] catalog,DriveCalculator needs,Dictionary<string,double> recoveryThreshold,double timeUnit)
    {
        this.actor=actor;this.needs=needs;this.recoveryThreshold=recoveryThreshold;this.timeUnit=timeUnit;
        var actions=catalog.ToDictionary(a=>a.Id,StringComparer.Ordinal);
        foreach(var entry in actor.Declaration.Get("planning").Get("physiology").Get("routes").Items())
        {
            if(routes.Count>=32)throw new InvalidDataException("Physiological routes exceed the fixed route budget.");
            var id=entry.Get("id").Text();var label=entry.Get("label").Text();var need=entry.Get("need").Text();
            var ids=entry.Get("actions").Items().Select(v=>v.Text()).ToArray();var recovery=entry.Get("recovery_action").Text();
            if(string.IsNullOrWhiteSpace(id)||string.IsNullOrWhiteSpace(label)||!recoveryThreshold.ContainsKey(need)||ids.Length is <1 or >8||
               ids.Any(action=>!actions.ContainsKey(action)||actions[action].Declaration.Get("manual_only").Flag())||ids.Count(action=>action==recovery)!=1||
               entry.Get("available_when").ValueKind!=JsonValueKind.Object||needs.CompletedEffect(actions[recovery],need)<=0)
                throw new InvalidDataException("A physiological route requires owned actions and a real positive recovery action: "+id);
            var sequence=ids.Select(action=>actions[action]).ToArray();
            if(!routes.TryAdd(id,new(id,label,need,Condition.Compile(entry.Get("available_when"),actor.Id),sequence,Array.IndexOf(ids,recovery),sequence.Sum(a=>a.Duration))))
                throw new InvalidDataException("Duplicate physiological route: "+id);
        }
    }

    internal ActionCandidate[] Candidates(string? urgent)
    {
        if(current is { } active)return [routes[active.Route].Actions[active.Index]];
        if(urgent is null)return [];
        return routes.Values.Where(r=>r.Need==urgent&&r.Available.Evaluate(actor.Recall)==Truth.True)
            .OrderBy(r=>r.EstimatedCost).Select(r=>r.Actions[0]).DistinctBy(a=>a.Id).ToArray();
    }

    internal ActionCandidate? Choose(IReadOnlyCollection<ActionCandidate> allowed,string? urgent,string? task,double now)
    {
        var ids=allowed.Select(a=>a.Id).ToHashSet(StringComparer.Ordinal);
        if(current is { } active)
        {
            var next=routes[active.Route].Actions[active.Index];
            return ids.Contains(next.Id)?next:null;
        }
        if(urgent is null)return null;
        var route=routes.Values.Where(r=>r.Need==urgent&&r.Available.Evaluate(actor.Recall)==Truth.True&&ids.Contains(r.Actions[0].Id))
            .OrderBy(r=>r.EstimatedCost).FirstOrDefault();
        if(route is null)return null;
        current=new(route.Id,0,task,now/timeUnit,needs.Snapshot(now)[route.Need],null,[]);
        return route.Actions[0];
    }

    internal void Complete(Decision decision,double now)
    {
        if(current is not { } active)return;
        var route=routes[active.Route];
        if(route.Actions[active.Index].Id!=decision.Action.Id)return;
        var value=needs.Snapshot(now)[route.Need];var steps=active.Steps.Append(new PhysiologicalStepReceipt(decision.Action.Id,decision.Execution,now/timeUnit,value)).ToArray();
        if(steps.Length>64)throw new InvalidDataException("Recovery route completion budget exceeded.");
        var recovered=active.RecoveredAt;
        var next=active.Index+1;
        if(active.Index==route.RecoveryIndex)
        {
            // Drinking is not credited merely because it was planned. If one
            // real serving is insufficient, repeat the same legal action.
            if(value<recoveryThreshold[route.Need])next=active.Index;
            else recovered=now/timeUnit;
        }
        current=active with {Index=next,RecoveredAt=recovered,Steps=steps};
        if(next==route.Actions.Length)Finish(now,"completed");
    }

    internal void ManualChoice(string action,string? task,double now)
    {
        if(current is { } active&&routes[active.Route].Actions[active.Index].Id!=action)Finish(now,"player_changed_action");
        if(current is not null)return;
        // Submit has already checked the player's chosen action against the
        // actual position and remembered evidence. Selecting a known route's
        // first step starts its record, without selecting any later action.
        // A player may replenish a low need before it becomes critical.
        var values=needs.Snapshot(now);
        var route=routes.Values.Where(r=>r.Actions[0].Id==action&&values[r.Need]<recoveryThreshold[r.Need]&&r.Available.Evaluate(actor.Recall)==Truth.True)
            .OrderBy(r=>r.EstimatedCost).FirstOrDefault();
        if(route is not null)current=new(route.Id,0,task,now/timeUnit,values[route.Need],null,[]);
    }
    private void Finish(double now,string outcome)
    {
        var active=current!;var route=routes[active.Route];
        recent.Add(new(route.Id,route.Need,active.InterruptedTask,active.StartedAt,active.RecoveredAt,now/timeUnit,active.NeedBefore,needs.Snapshot(now)[route.Need],outcome,active.Steps.ToArray()));
        if(recent.Count>16)recent.RemoveAt(0);
        current=null;
    }
    internal string Explanation=>current is not { } c?"":c.Index>routes[c.Route].RecoveryIndex?
        "身体需要已经实际恢复，正在沿已知路线回到"+(c.InterruptedTask is null?"原来所在的地点。":"原任务地点。"):
        "沿本人已知的合法路线前往实际水源或恢复设施。";
    internal object? View()=>current is not { } c?null:new {id=c.Route,label=routes[c.Route].Label,need=routes[c.Route].Need,
        step=c.Index+1,total_steps=routes[c.Route].Actions.Length,returning=c.Index>routes[c.Route].RecoveryIndex,
        started_at=c.StartedAt,recovered_at=c.RecoveredAt,completed_actions=c.Steps.ToArray()};
    internal object[] Receipts()=>recent.Select(r=>(object)new {route=r.Route,need=r.Need,task=r.Task,started_at=r.StartedAt,recovered_at=r.RecoveredAt,
        finished_at=r.FinishedAt,need_before=r.NeedBefore,need_after=r.NeedAfter,outcome=r.Outcome,steps=r.Steps.ToArray()}).ToArray();
    internal PhysiologicalRoutesState Save()=>new(current is { } c?c with {Steps=c.Steps.ToArray()}:null,recent.Select(r=>r with {Steps=r.Steps.ToArray()}).ToArray());
    internal void Restore(PhysiologicalRoutesState? state)
    {
        if(state is null){if(routes.Count>0)throw new InvalidDataException("New physiological routes require a new game.");current=null;recent.Clear();return;}
        if(state.Recent is null||state.Recent.Length>16)throw new InvalidDataException("Invalid recovery route history.");
        if(state.Current is { } c)
        {
            if(!routes.TryGetValue(c.Route,out var route)||c.Index<0||c.Index>=route.Actions.Length||!Finite(c.StartedAt)||!Value(c.NeedBefore)||c.Steps is null||c.Steps.Length>64||
               c.RecoveredAt is { } recovered&&(!Finite(recovered)||recovered<c.StartedAt)||c.Steps.Any(s=>!Valid(s)))throw new InvalidDataException("Invalid saved physiological route.");
        }
        foreach(var r in state.Recent)
            if(!routes.ContainsKey(r.Route)||!Finite(r.StartedAt)||!Finite(r.FinishedAt)||r.FinishedAt<r.StartedAt||!Value(r.NeedBefore)||!Value(r.NeedAfter)||r.Steps is null||r.Steps.Length>64||r.Steps.Any(s=>!Valid(s)))
                throw new InvalidDataException("Invalid recovery route receipt.");
        current=state.Current is { } saved?saved with {Steps=saved.Steps.ToArray()}:null;recent.Clear();recent.AddRange(state.Recent.Select(r=>r with {Steps=r.Steps.ToArray()}));
    }
    private static bool Finite(double value)=>double.IsFinite(value)&&value>=0;
    private static bool Value(double value)=>Finite(value)&&value<=100;
    private static bool Valid(PhysiologicalStepReceipt step)=>!string.IsNullOrWhiteSpace(step.Action)&&step.Execution>0&&Finite(step.Time)&&Value(step.NeedValue);
}
