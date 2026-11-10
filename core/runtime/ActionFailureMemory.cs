using System.Text.Json;

namespace DuelView.Runtime;

public sealed record ActionFailureBasis(FieldKey Key,Fact? Fact);
public sealed record ActionFailureCheckpoint(string Action,string Reason,int Attempts,double LastAttempt,double RetryAt,
    double BasePenalty,ActionFailureBasis[] Basis,bool RefreshPending,bool Active=true,string ReleaseReason="",string[]? Resources=null,
    string RetryPolicy="interval");

/// <summary>A remembered failed attempt changes utility, not the set of known actions.
/// Only the actor's own relevant evidence, or an authored retry interval, releases it.</summary>
internal sealed class ActionFailureMemory
{
    private readonly ActorClient actor;
    private readonly Dictionary<string,ActionCandidate> actions;
    private readonly Dictionary<string,ActionFailureCheckpoint> memories=new(StringComparer.Ordinal);
    private readonly double minimumPenalty,retrySeconds,resourceRetrySeconds;
    internal long Revision {get;private set;}
    internal ActionFailureMemory(ActorClient actor,IEnumerable<ActionCandidate> catalog,double timeUnit)
    {
        this.actor=actor;actions=catalog.ToDictionary(action=>action.Id,StringComparer.Ordinal);
        var declaration=actor.Declaration.Get("autonomy").Get("failure_memory");
        minimumPenalty=declaration.Get("penalty").Number(100);
        retrySeconds=declaration.Get("retry_minutes").Number(45)*timeUnit;
        resourceRetrySeconds=declaration.Get("resource_retry_minutes").Number(1)*timeUnit;
        if(!double.IsFinite(minimumPenalty)||minimumPenalty<=0||!double.IsFinite(retrySeconds)||retrySeconds<=0||!double.IsFinite(resourceRetrySeconds)||resourceRetrySeconds<=0)
            throw new InvalidDataException("Failure memory needs a positive utility penalty and finite retry interval.");
    }
    internal ActionFailureCheckpoint? Record(ActionCandidate action,bool success,string reason,IEnumerable<FieldKey> basis,double now,double score,string[]? blockedResources=null)
    {
        if(success){if(memories.Remove(action.Id))Revision++;return null;}
        if(reason=="cancelled")return null;
        var prior=Read(action.Id,now,true);
        var resource=reason=="standing_resource_busy";
        var resources=resource?(blockedResources??action.Declaration.Get("resource_reservations").Items().Select(item=>item.Text()).ToArray()).Order(StringComparer.Ordinal).ToArray():null;
        var sameResource=resource&&prior?.Reason==reason&&prior.Resources is not null&&prior.Resources.SequenceEqual(resources!,StringComparer.Ordinal);
        var attempts=resource?sameResource?Math.Min(8,prior!.Attempts+1):1:prior is {Active:true}?Math.Min(8,prior.Attempts+1):1;
        var knownBlockers=reason=="objective_condition_failed"?KnownBlockers(action):[];
        var keys=(knownBlockers.Length>0?knownBlockers:basis).Distinct().Take(128).ToArray();
        var retry=resource?resourceRetrySeconds*Math.Min(8,Math.Pow(2,attempts-1)):retrySeconds*Math.Min(4,attempts);
        var memory=new ActionFailureCheckpoint(action.Id,reason,attempts,now,now+retry,
            Math.Max(minimumPenalty,Math.Abs(score)+1),keys.Select(key=>new ActionFailureBasis(key,actor.Recall(key))).ToArray(),actor.IsUpdating||actor.IsObserving,
            Resources:resources,RetryPolicy:knownBlockers.Length>0?"evidence_change":resource?"resource_backoff":"interval");
        memories[action.Id]=memory;Revision++;
        return memory;
    }
    private ActionFailureCheckpoint? Read(string action,double now,bool update=false)
    {
        if(!memories.TryGetValue(action,out var memory))return null;
        if(memory.RefreshPending&&!actor.IsUpdating&&!actor.IsObserving)
        {
            var knownBlockers=memory.Reason=="objective_condition_failed"?KnownBlockers(actions[memory.Action]):[];
            memory=memory with {Basis=(knownBlockers.Length>0?knownBlockers:memory.Basis.Select(item=>item.Key))
                .Select(key=>new ActionFailureBasis(key,actor.Recall(key))).ToArray(),RefreshPending=false,
                RetryPolicy=knownBlockers.Length>0?"evidence_change":memory.RetryPolicy};
            if(update){memories[action]=memory;Revision++;}
        }
        if(memory.Active)
        {
            var changed=!memory.RefreshPending&&memory.Basis.Any(item=>!Same(item.Fact,actor.Recall(item.Key)));
            if(changed||memory.RetryPolicy!="evidence_change"&&now>=memory.RetryAt)
            {
                memory=memory with {Active=false,ReleaseReason=changed?"relevant_owned_evidence_changed":"retry_interval_elapsed"};
                if(update){memories[action]=memory;Revision++;}
            }
        }
        return memory;
    }
    private FieldKey[] KnownBlockers(ActionCandidate action)
    {
        IEnumerable<FieldKey> FalseInputs(Condition condition)
        {
            if(condition.Evaluate(actor.Recall)!=Truth.False)return [];
            return condition is Condition.All all?all.Items.SelectMany(FalseInputs):condition.Inputs;
        }
        var objective=action.Declaration.Get("objective_gate");
        return FalseInputs(action.Gate).Concat(objective.ValueKind==JsonValueKind.Object?
            FalseInputs(Condition.Compile(objective,actor.Id)):[])
            .Where(key=>actor.Recall(key) is {Known:true,Conflicted:false}).Distinct().Take(128).ToArray();
    }
    // Seeing the same empty container again is fresh evidence, but it does not
    // remove the known obstacle. Keep versions in the audit without treating a
    // same-value refresh as a new opportunity to repeat the failed action.
    private static bool Same(Fact? before,Fact? after)=>before is null?after is null:after is not null&&
        before.Known==after.Known&&before.Conflicted==after.Conflicted&&before.Confidence==after.Confidence&&Values.Same(before.Value,after.Value);
    internal double Penalty(string action,double now)=>Read(action,now) is {Active:true} memory?memory.BasePenalty*memory.Attempts:0;
    internal void Refresh(double now){foreach(var action in memories.Keys.ToArray())Read(action,now,true);}
    internal object Audit(double now)=>memories.Keys.ToArray().Select(action=>Read(action,now)).Where(item=>item is not null).ToArray();
    internal ActionFailureCheckpoint[] Save()=>memories.Values.ToArray();
    internal void Restore(ActionFailureCheckpoint[]? state)
    {
        memories.Clear();
        foreach(var memory in state??[])
        {
            if(!actions.ContainsKey(memory.Action)||string.IsNullOrWhiteSpace(memory.Reason)||memory.Attempts is <1 or >8||
                !double.IsFinite(memory.LastAttempt)||memory.LastAttempt<0||!double.IsFinite(memory.RetryAt)||memory.RetryAt<memory.LastAttempt||
                !double.IsFinite(memory.BasePenalty)||memory.BasePenalty<=0||memory.Basis is null||memory.Basis.Length>128||
                memory.Basis.Select(item=>item.Key).Distinct().Count()!=memory.Basis.Length||
                memory.RetryPolicy is not ("interval" or "resource_backoff" or "evidence_change")||
                memory.RetryPolicy=="evidence_change"&&(memory.Reason!="objective_condition_failed"||memory.Basis.Length==0)||
                memory.RetryPolicy=="resource_backoff"&&memory.Reason!="standing_resource_busy"||
                memory.Resources is { } resources&&(resources.Any(string.IsNullOrWhiteSpace)||resources.Distinct(StringComparer.Ordinal).Count()!=resources.Length)||!memories.TryAdd(memory.Action,memory))
                throw new InvalidDataException("Incompatible action failure memory checkpoint.");
        }
        Revision++;
    }
}
