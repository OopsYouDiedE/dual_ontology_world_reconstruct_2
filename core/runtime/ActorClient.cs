using System.Text.Json;

namespace DuelView.Runtime;

public enum InformationOrigin { Passive, Communication, DeliberateObservation, ActionFailure, ActionFeedback }
public enum RefreshCause { Deliberate, FailedAction, ObservationEnded, ActionCompleted }
public sealed record Observation(string Id, FieldKey Key, JsonElement Value, double Confidence, double Time,
    InformationOrigin Origin, JsonElement Source, string? MapElement = null);
public sealed record Evidence(string Id, FieldKey Key, JsonElement Value, double Confidence, double Time,
    string Method, JsonElement Source);
public sealed record ClientView(string Actor, long KnowledgeRevision, long MapRevision,
    IReadOnlyDictionary<FieldKey, Fact> Knowledge, IReadOnlyDictionary<string, JsonElement> RememberedMap);
public sealed record InferenceConclusionCheckpoint(string Rule,FieldKey Key);
public sealed record RefreshWorkState(RefreshCause Cause,Observation[] Remaining,bool InputFinished,SavedFact[] Writes,
    Dictionary<string,JsonElement> Map,Evidence[] Evidence,string[] Queue,InferenceConclusionCheckpoint[] Conclusions);
public sealed record ActorClientState(string Actor,FactStoreState Knowledge,Evidence[] Evidence,Observation[] Inbox,
    Dictionary<string,JsonElement> RememberedMap,FieldKey[] ExplicitFocus,FieldKey[] ActionFocus,string? ObservationToken,
    long NextObservation,long MapRevision,long ReceivedCount,long IgnoredCount,long RefreshCount,long InferenceEvaluations,RefreshWorkState? Refresh);

/// <summary>
/// An actor owns a persistent subjective replica. Reception only runs an inexpensive
/// attention filter; it never mutates knowledge or launches reasoning. Player and AI
/// both read this same replica and submit commands through the server.
/// </summary>
public sealed class ActorClient
{
    private readonly FactStore knowledge;
    private readonly Dictionary<string, Rule> inference = new(StringComparer.Ordinal);
    private readonly Dictionary<FieldKey, HashSet<string>> inferenceReaders = [];
    private Dictionary<FieldKey, List<Observation>> inbox = [];
    private HashSet<(string, FieldKey)> pendingIds = [];
    private readonly List<Evidence> evidence = [];
    private readonly Dictionary<string, JsonElement> rememberedMap = new(StringComparer.Ordinal);
    private readonly HashSet<FieldKey> explicitFocus = [];
    private readonly HashSet<FieldKey> actionFocus = [];
    private readonly HashSet<FieldKey> goalFocus = [];
    private readonly JsonElement attention;
    private readonly JsonElement goals;
    private RefreshWork? refresh;
    private ClientView? cachedView;
    private string? observationToken;
    private long nextObservation;
    private readonly SingleStepPolicy singleStep;
    public string Id { get; }
    public long KnowledgeRevision => knowledge.Revision;
    public long MapRevision { get; private set; }
    public long ReceivedCount { get; private set; }
    public long IgnoredCount { get; private set; }
    public long RefreshCount { get; private set; }
    public long InferenceEvaluations { get; private set; }
    public bool IsObserving => observationToken is not null;
    public bool IsUpdating => refresh is not null;
    public int PendingInformation => pendingIds.Count;
    public IReadOnlyList<Evidence> Evidence => evidence.AsReadOnly();
    public JsonElement Declaration { get; }

    internal ActorClient(JsonElement declaration, JsonElement attentionPolicy)
    {
        Id = declaration.Get("id").Text();
        if (Id.Length == 0) throw new InvalidDataException("Actor identity is required.");
        Declaration = declaration;
        attention = attentionPolicy;
        foreach (var rule in attention.Get("rules").Items())
        {
            var kind = rule.Get("kind").Text();
            if (kind is not ("deliberate_focus" or "failed_action_focus" or "current_action" or "current_goal" or "known_conflict" or "field"))
                throw new InvalidDataException("Unsupported attention rule: " + kind);
            if (kind == "field") _ = FieldKey.Read(rule.Get("ref"), Id);
            if (rule.Get("when").ValueKind == JsonValueKind.Object) _ = Condition.Compile(rule.Get("when"), Id);
        }
        goals = declaration.Get("policy").Get("goals");
        knowledge = new(Id);
        var mind = declaration.Get("mind");
        if (mind.Get("subject").Text() != Id) throw new InvalidDataException("Actor owns another subject's initial knowledge.");
        knowledge.Initialize(mind.Get("objects"));
        foreach (var adoption in mind.Get("adoptions").Fields())
        {
            if (!adoption.Value.Get("active").Flag(true) || adoption.Value.Get("mode").Text() != "infer") continue;
            var rule = Rule.Compile(adoption.Name, adoption.Value, Id);
            inference.Add(rule.Id, rule);
            foreach (var key in rule.Premise.Inputs)
            {
                if (!inferenceReaders.TryGetValue(key, out var readers)) inferenceReaders.Add(key, readers = []);
                readers.Add(rule.Id);
            }
        }
        RebuildGoalFocus();
        singleStep = new(this);
    }

    public Fact? Recall(FieldKey key) => knowledge.Read(key);
    public ActorClientState SaveState()
    {
        RefreshWorkState? pending=null;
        if(refresh is { } work)
        {
            var remaining=new List<Observation>();
            if(!work.InputFinished)while(work.Incoming.MoveNext())remaining.Add(work.Incoming.Current);
            work.Incoming.Dispose();work.Incoming=remaining.GetEnumerator();
            pending=new(work.Cause,remaining.ToArray(),work.InputFinished,work.Writes.Select(item=>new SavedFact(item.Key,item.Value)).ToArray(),
                new(work.Map,StringComparer.Ordinal),work.Evidence.ToArray(),work.Queue.ToArray(),work.Conclusions.Select(item=>new InferenceConclusionCheckpoint(item.Item1,item.Item2)).ToArray());
        }
        return new(Id,knowledge.SaveState(),evidence.ToArray(),inbox.Values.SelectMany(items=>items).ToArray(),
            new(rememberedMap,StringComparer.Ordinal),explicitFocus.ToArray(),actionFocus.ToArray(),observationToken,nextObservation,
            MapRevision,ReceivedCount,IgnoredCount,RefreshCount,InferenceEvaluations,pending);
    }
    public void RestoreState(ActorClientState state)
    {
        if(state.Actor!=Id || state.NextObservation<0 || state.MapRevision<0 || state.ReceivedCount<0 || state.IgnoredCount<0 || state.RefreshCount<0 || state.InferenceEvaluations<0 ||
           state.Evidence is null || state.Inbox is null || state.RememberedMap is null || state.ExplicitFocus is null || state.ActionFocus is null)
            throw new InvalidDataException("Invalid actor checkpoint.");
        var seen=new HashSet<(string,FieldKey)>();
        static bool ValidKey(FieldKey key)=>!string.IsNullOrWhiteSpace(key.Object)&&!string.IsNullOrWhiteSpace(key.Facet)&&!string.IsNullOrWhiteSpace(key.Field);
        static bool ValidEvidence(Evidence item)=>item is not null && !string.IsNullOrWhiteSpace(item.Id) && ValidKey(item.Key) && item.Value.ValueKind!=JsonValueKind.Undefined && item.Source.ValueKind!=JsonValueKind.Undefined &&
            !string.IsNullOrWhiteSpace(item.Method) && double.IsFinite(item.Confidence) && item.Confidence is >=0 and <=1 && double.IsFinite(item.Time) && item.Time>=0;
        foreach(var item in state.Evidence)
            if(!ValidEvidence(item))
                throw new InvalidDataException("Invalid evidence in actor checkpoint.");
        foreach(var item in state.Inbox)
            if(item is null || string.IsNullOrWhiteSpace(item.Id) || !ValidKey(item.Key) || item.Value.ValueKind==JsonValueKind.Undefined || item.Source.ValueKind==JsonValueKind.Undefined ||
               !seen.Add((item.Id,item.Key)) || !double.IsFinite(item.Confidence) || item.Confidence is <0 or >1 || !double.IsFinite(item.Time) || item.Time<0)
                throw new InvalidDataException("Invalid buffered observation in checkpoint.");
        if(state.RememberedMap.Any(item=>string.IsNullOrWhiteSpace(item.Key)||item.Value.ValueKind==JsonValueKind.Undefined) ||
           state.ExplicitFocus.Any(key=>!ValidKey(key)) || state.ActionFocus.Any(key=>!ValidKey(key)))throw new InvalidDataException("Invalid remembered map or focus in actor checkpoint.");
        if(state.Refresh is { } staged && (staged.Remaining is null || staged.Writes is null || staged.Map is null || staged.Evidence is null || staged.Queue is null || staged.Conclusions is null ||
           staged.Remaining.Any(item=>item is null || !ValidKey(item.Key) || item.Value.ValueKind==JsonValueKind.Undefined || item.Source.ValueKind==JsonValueKind.Undefined) ||
           staged.Writes.Any(item=>!ValidKey(item.Key) || item.Fact is null || item.Fact.Value.ValueKind==JsonValueKind.Undefined) ||
           staged.Queue.Distinct(StringComparer.Ordinal).Count()!=staged.Queue.Length || staged.Queue.Any(id=>!inference.ContainsKey(id)) ||
           staged.Conclusions.Any(item=>!inference.ContainsKey(item.Rule)||!ValidKey(item.Key)) || staged.Evidence.Any(item=>!ValidEvidence(item)) || staged.Map.Any(item=>item.Value.ValueKind==JsonValueKind.Undefined)))
            throw new InvalidDataException("Invalid cognitive work checkpoint.");
        knowledge.RestoreState(state.Knowledge);
        evidence.Clear();evidence.AddRange(state.Evidence);
        inbox.Clear();pendingIds.Clear();
        foreach(var item in state.Inbox)
        {
            if(!inbox.TryGetValue(item.Key,out var bucket))inbox.Add(item.Key,bucket=[]);
            bucket.Add(item);pendingIds.Add((item.Id,item.Key));
        }
        rememberedMap.Clear();foreach(var item in state.RememberedMap)rememberedMap.Add(item.Key,item.Value.Clone());
        explicitFocus.Clear();explicitFocus.UnionWith(state.ExplicitFocus);actionFocus.Clear();actionFocus.UnionWith(state.ActionFocus);
        observationToken=state.ObservationToken;nextObservation=state.NextObservation;MapRevision=state.MapRevision;
        ReceivedCount=state.ReceivedCount;IgnoredCount=state.IgnoredCount;RefreshCount=state.RefreshCount;InferenceEvaluations=state.InferenceEvaluations;
        refresh=null;
        if(state.Refresh is { } saved)
        {
            var work=new RefreshWork(saved.Cause,((IEnumerable<Observation>)saved.Remaining).GetEnumerator()) {InputFinished=saved.InputFinished};
            foreach(var item in saved.Writes)work.Writes.Add(item.Key,item.Fact);
            foreach(var item in saved.Map)work.Map.Add(item.Key,item.Value.Clone());
            work.Evidence.AddRange(saved.Evidence);foreach(var id in saved.Queue){work.Queue.Enqueue(id);work.Queued.Add(id);}
            foreach(var item in saved.Conclusions)work.Conclusions.Add((item.Rule,item.Key));refresh=work;
        }
        cachedView=null;RebuildGoalFocus();
    }
    internal double GoalScore(ActionCandidate action, double contentTime) => singleStep.Score(action, contentTime);

    public ClientView View()
    {
        // No world version or clock is part of this key. Unrelated events, incoming
        // messages, render frames and movement do not regenerate a mental map.
        return cachedView ??= new(Id, KnowledgeRevision, MapRevision,
            new System.Collections.ObjectModel.ReadOnlyDictionary<FieldKey, Fact>(knowledge.Entries.ToDictionary()),
            new System.Collections.ObjectModel.ReadOnlyDictionary<string, JsonElement>(new Dictionary<string, JsonElement>(rememberedMap)));
    }

    internal void FocusAction(IEnumerable<FieldKey> keys)
    {
        actionFocus.Clear();
        actionFocus.UnionWith(keys);
    }

    private void RebuildGoalFocus()
    {
        goalFocus.Clear();
        foreach (var goal in goals.Items())
        {
            var gate = goal.Get("available_when");
            if (gate.ValueKind == JsonValueKind.Object && Condition.Compile(gate, Id).Evaluate(knowledge.Read) == Truth.False) continue;
            if (goal.Get("ref").ValueKind == JsonValueKind.Object) goalFocus.Add(FieldKey.Read(goal.Get("ref"), Id));
            if (gate.ValueKind == JsonValueKind.Object) goalFocus.UnionWith(Condition.Compile(gate, Id).Inputs);
        }
    }

    internal bool Receive(Observation information)
    {
        ReceivedCount++;
        if (!double.IsFinite(information.Confidence) || information.Confidence is < 0 or > 1 || !double.IsFinite(information.Time))
            throw new InvalidDataException("Invalid observation measurement.");
        if (!IsImportant(information)) { IgnoredCount++; return false; }
        return Enqueue(information);
    }
    internal bool ReceiveDirected(Observation information)
    {
        ReceivedCount++;
        if(information.Origin!=InformationOrigin.Communication || !double.IsFinite(information.Confidence) || information.Confidence is < 0 or > 1 || !double.IsFinite(information.Time))
            throw new InvalidDataException("Invalid directed communication.");
        return Enqueue(information);
    }
    internal bool ReceiveSalient(Observation information)
    {
        if(information.Origin!=InformationOrigin.Passive)throw new InvalidDataException("Expected a physical perception.");
        ReceivedCount++;
        return Enqueue(information);
    }
    private bool Enqueue(Observation information)
    {
        if (!pendingIds.Add((information.Id, information.Key))) return false;
        if (!inbox.TryGetValue(information.Key, out var entries)) inbox.Add(information.Key, entries = []);
        entries.Add(information);
        return true;
    }

    private bool IsImportant(Observation item)
    {
        if (item.Confidence < attention.Get("minimum_confidence").Number()) return false;
        foreach (var rule in attention.Get("rules").Items())
        {
            var relevant = rule.Get("kind").Text() switch
            {
                "deliberate_focus" => item.Origin == InformationOrigin.DeliberateObservation && explicitFocus.Contains(item.Key),
                "failed_action_focus" => item.Origin == InformationOrigin.ActionFailure && actionFocus.Contains(item.Key),
                "current_action" => actionFocus.Contains(item.Key),
                "current_goal" => goalFocus.Contains(item.Key),
                "known_conflict" => knowledge.Read(item.Key) is { Known: true } old && !Values.Same(old.Value, item.Value),
                "field" => FieldKey.Read(rule.Get("ref"), Id) == item.Key,
                _ => throw new InvalidDataException("Unsupported attention rule: " + rule.Get("kind").Text())
            };
            if (!relevant) continue;
            var condition = rule.Get("when");
            if (condition.ValueKind != JsonValueKind.Object || Condition.Compile(condition, Id).Evaluate(knowledge.Read) == Truth.True)
                return true;
        }
        return false;
    }

    internal string BeginObservation(IEnumerable<FieldKey> focus)
    {
        if (IsObserving) throw new InvalidOperationException("This actor is already observing.");
        explicitFocus.Clear();
        explicitFocus.UnionWith(focus);
        observationToken = $"{Id}/observation/{++nextObservation}";
        return observationToken;
    }

    internal void EndObservation(string token)
    {
        if (token != observationToken) throw new InvalidOperationException("Observation completion belongs to another interval.");
        observationToken = null;
        explicitFocus.Clear();
        BeginRefresh(RefreshCause.ObservationEnded);
    }

    internal void BeginRefresh(RefreshCause cause)
    {
        if (IsObserving && cause != RefreshCause.ObservationEnded)
            throw new InvalidOperationException("Finish the observation interval before committing its batch.");
        if (refresh is not null) throw new InvalidOperationException("This actor already has an active knowledge update.");
        if (inbox.Count == 0) return;
        // Detach in constant time. New arrivals belong to the next deliberate batch.
        refresh = new RefreshWork(cause, inbox.Values.SelectMany(x => x).GetEnumerator());
        inbox = [];
        pendingIds = [];
    }

    internal void BeginActionFeedback(IEnumerable<Observation> samples)
    {
        if (IsObserving || refresh is not null) throw new InvalidOperationException("Actor already owns a cognitive activity.");
        // Action feedback is its own batch. Unprocessed ambient messages stay buffered.
        refresh = new RefreshWork(RefreshCause.ActionCompleted, samples.Where(IsImportant).ToList().GetEnumerator());
    }

    internal void ProcessDirectedMessages()
    {
        if(IsObserving || refresh is not null)return;
        var messages=inbox.Values.SelectMany(items=>items).Where(item=>item.Origin==InformationOrigin.Communication||item.Id.StartsWith("perception/",StringComparison.Ordinal)).ToArray();
        if(messages.Length==0)return;
        foreach(var message in messages)
        {
            var bucket=inbox[message.Key];bucket.Remove(message);
            if(bucket.Count==0)inbox.Remove(message.Key);
            pendingIds.Remove((message.Id,message.Key));
        }
        // A direct report received while working is considered at the next free moment.
        // Ambient observations remain buffered until deliberate attention.
        refresh=new RefreshWork(RefreshCause.Deliberate,((IEnumerable<Observation>)messages).GetEnumerator());
    }

    private void EnqueueReaders(RefreshWork work, FieldKey key)
    {
        if (!inferenceReaders.TryGetValue(key, out var readers)) return;
        foreach (var reader in readers) if (work.Queued.Add(reader)) work.Queue.Enqueue(reader);
    }

    internal bool ContinueRefresh(int ruleBudget)
    {
        if (ruleBudget < 1) throw new ArgumentOutOfRangeException(nameof(ruleBudget));
        if (refresh is not { } work) return true;
        var remaining = ruleBudget;
        while (!work.InputFinished && remaining > 0)
        {
            remaining--;
            if (!work.Incoming.MoveNext()) { work.InputFinished = true; work.Incoming.Dispose(); break; }
            var sample = work.Incoming.Current;
            var key = sample.Key;
            work.Evidence.Add(new(sample.Id, key, sample.Value, sample.Confidence, sample.Time, "observation", sample.Source));
            var before = work.Writes.GetValueOrDefault(key) ?? knowledge.Read(key);
            if (before is { Known: true } && (sample.Time < before.ObservedAt || sample.Time == before.ObservedAt && sample.Confidence < before.Confidence)) continue;
            var tied = before is { Known: true } && sample.Time == before.ObservedAt && sample.Confidence == before.Confidence;
            var conflicted = tied && (before!.Conflicted || !Values.Same(before.Value, sample.Value));
            work.Writes[key] = new(sample.Value, true, conflicted, sample.Confidence, sample.Time, 0);
            if (sample.MapElement is { Length: > 0 } map) work.Map[map] = sample.Value;
            EnqueueReaders(work, key);
        }
        if (!work.InputFinished) return false;
        Fact? Read(FieldKey key) => work.Writes.GetValueOrDefault(key) ?? knowledge.Read(key);
        for (var count = 0; count < remaining && work.Queue.TryDequeue(out var id); count++)
        {
            work.Queued.Remove(id);
            InferenceEvaluations++;
            var rule = inference[id];
            if (rule.Premise.Evaluate(Read) != Truth.True) continue;
            var inputs = rule.Premise.Inputs.Select(Read).Where(f => f is not null).Cast<Fact>().ToArray();
            var confidence = inputs.Select(f => f.Confidence).Append(rule.Confidence).Min();
            var time = inputs.Select(f => f.ObservedAt).DefaultIfEmpty().Max();
            foreach (var (key, inferred) in rule.Preview(Read, time))
            {
                var old = Read(key);
                // Inference does not erase better supported observations. Contradictory
                // equally supported conclusions remain explicitly conflicted.
                if (old is { Known: true } && old.Confidence > confidence) continue;
                var candidate = inferred with { Confidence = confidence,
                    Conflicted = old is { Known: true } && old.Confidence == confidence && !Values.Same(old.Value, inferred.Value) };
                if (old is not null && Values.Same(old.Value, candidate.Value) && old.Confidence == candidate.Confidence && old.Conflicted == candidate.Conflicted) continue;
                if (!work.Conclusions.Add((id, key))) continue;
                work.Writes[key] = candidate;
                work.Evidence.Add(new(id, key, candidate.Value, confidence, time, "inference",
                    JsonSerializer.SerializeToElement(new {rule=id,basis=rule.Basis.ValueKind==JsonValueKind.Undefined?JsonSerializer.SerializeToElement<object?>(null):rule.Basis,
                        premises=rule.Premise.Inputs.Select(input=>new {key=input,value=Read(input)?.Value,evidence_ids=evidence.Concat(work.Evidence).Where(e=>e.Key==input).Select(e=>e.Id).Distinct().ToArray()}).ToArray()})));
                EnqueueReaders(work, key);
            }
        }
        if (work.Queue.Count > 0) return false;
        var changes = knowledge.Apply(work.Writes);
        evidence.AddRange(work.Evidence);
        var mapChanged = false;
        foreach (var (key, value) in work.Map)
        {
            if (rememberedMap.TryGetValue(key, out var old) && Values.Same(old, value)) continue;
            rememberedMap[key] = value;
            mapChanged = true;
        }
        if (mapChanged) MapRevision++;
        if (changes.Count > 0 || mapChanged) cachedView = null;
        RefreshCount++;
        refresh = null;
        if (changes.Count > 0) RebuildGoalFocus();
        return true;
    }

    private sealed class RefreshWork(RefreshCause cause, IEnumerator<Observation> incoming)
    {
        internal IEnumerator<Observation> Incoming { get; set; } = incoming;
        internal bool InputFinished;
        internal RefreshCause Cause { get; } = cause;
        internal Dictionary<FieldKey, Fact> Writes { get; } = [];
        internal Dictionary<string, JsonElement> Map { get; } = [];
        internal List<Evidence> Evidence { get; } = [];
        internal Queue<string> Queue { get; } = [];
        internal HashSet<string> Queued { get; } = [];
        internal HashSet<(string, FieldKey)> Conclusions { get; } = [];
    }
}
