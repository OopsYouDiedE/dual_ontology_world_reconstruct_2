using System.Text.Json;
using DuelView.Core;

namespace DuelView.Runtime;

public sealed record StrategyActivityState(long Revision,double Due,bool Active,long Operations,bool WasComputing,CaseStrategyChoice[]? Cached);

/// <summary>An explicitly started, time-consuming activity. Ordinary autonomy never
/// invokes proof search. Results are cached against the owner's knowledge revision.</summary>
public sealed class StrategyActivity : IDisposable
{
    private readonly ActorClient owner;
    private readonly CaseTheory authored;
    private readonly JsonElement profile;
    private readonly JsonElement[] mappings;
    private readonly double contentTimeUnit;
    private readonly CaseLiteral? activityLiteral;
    private StrategyJudgment.CaseStrategyWork? work;
    private IReadOnlyList<CaseStrategyChoice>? cached;
    private long revision = -1;
    private double due;
    private bool active;
    public bool Computing => work is not null;
    public bool Active => active;
    public long Operations { get; private set; }
    public StrategyActivityState SaveState()=>new(revision,due,active,Operations,work is not null,cached?.ToArray());
    public void RestoreState(StrategyActivityState state)
    {
        if(state.Revision< -1 || !double.IsFinite(state.Due)||state.Due<0 || state.Operations<0 || state.WasComputing && !state.Active || state.WasComputing && state.Cached is not null)
            throw new InvalidDataException("Invalid strategy checkpoint.");
        work?.Dispose();work=null;revision=state.Revision;due=state.Due;active=state.Active;Operations=state.Operations;cached=state.Cached;
        if(state.WasComputing)Restart();
    }

    public StrategyActivity(ActorClient owner, CaseTheory authored, JsonElement profile, JsonElement evidenceMappings, double contentTimeUnit,JsonElement activityEvidence=default)
    {
        this.owner = owner;
        this.authored = authored;
        this.profile = profile.Clone();
        if (!double.IsFinite(contentTimeUnit) || contentTimeUnit <= 0) throw new ArgumentOutOfRangeException(nameof(contentTimeUnit));
        this.contentTimeUnit = contentTimeUnit;
        if(activityEvidence.ValueKind==JsonValueKind.Object)
        {
            activityLiteral=activityEvidence.Deserialize<CaseLiteral>(new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                ?? throw new InvalidDataException("Invalid activity evidence literal.");
            if(!activityLiteral.Ground)throw new InvalidDataException("Activity evidence must be ground.");
        }
        var actor = profile.Get("runtime_actor").Text(profile.Get("actor").Text());
        if (actor != owner.Id || profile.Get("actor").Text() == "objective") throw new InvalidDataException("Strategy activity belongs to another actor.");
        mappings = evidenceMappings.Items().Where(x => x.Get("actor").Text() == owner.Id).ToArray();
    }

    public void Begin(double now, double authoredDuration)
    {
        if (active) throw new InvalidOperationException("Strategy activity already running.");
        if (!double.IsFinite(now) || now < 0 || !double.IsFinite(authoredDuration) || authoredDuration <= 0 || !double.IsFinite(now + authoredDuration * contentTimeUnit))
            throw new InvalidDataException("Strategy activity needs a finite positive DV duration.");
        due = now + authoredDuration * contentTimeUnit;
        active = true;
        if (cached is null || revision != owner.KnowledgeRevision) Restart();
    }

    private void Restart()
    {
        work?.Dispose();
        cached = null;
        revision = owner.KnowledgeRevision;
        var scope = profile.Get("actor").Text();
        var evidence = new List<CaseAxiom>();
        if(activityLiteral is not null)evidence.Add(new("activity/started",activityLiteral,"actor:"+owner.Id+":active-work"));
        foreach (var mapping in mappings)
        {
            var reference=mapping.Get("reference");
            var key = reference.Get("type").Text()=="ref" ? FieldKey.Read(reference,owner.Id)
                : new FieldKey(reference.Get("object").Text(),reference.Get("facet").Text(),reference.Get("field").Text());
            if(string.IsNullOrWhiteSpace(key.Object)||string.IsNullOrWhiteSpace(key.Facet)||string.IsNullOrWhiteSpace(key.Field))
                throw new InvalidDataException("Invalid strategy evidence reference: "+mapping.Get("id").Text());
            if (owner.Recall(key) is not { Known: true, Conflicted: false } fact || !Values.Same(fact.Value, mapping.Get("equals"))) continue;
            var literal = mapping.Get("literal").Deserialize<CaseLiteral>(new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                ?? throw new InvalidDataException("Invalid DV strategy evidence literal.");
            evidence.Add(new("knowledge/" + mapping.Get("id").Text() + "/" + fact.Revision, literal, "actor:" + owner.Id));
        }
        // Scenario axioms are authoring fixtures, not the actor's live memory.
        // Stable personal values must be explicitly named in the profile.
        foreach(var item in profile.Get("intrinsic_axioms").Items())
        {
            var id=item.Text();
            var matches=authored.Scopes[scope].Axioms.Where(x=>x.Id==id).ToArray();
            if(matches.Length!=1)throw new InvalidDataException("Unknown intrinsic strategy axiom: "+id);
            evidence.Add(matches[0]);
        }
        var theory = authored.WithoutAssumptions(scope).WithEvidence(scope, evidence);
        work = StrategyJudgment.BeginEvaluation(theory, scope, profile);
    }

    public void Step(int operationBudget, TimeSpan timeBudget)
    {
        if (!active) return;
        if (owner.IsUpdating) return;
        if (revision != owner.KnowledgeRevision) Restart();
        if (work is null) return;
        var slice = work.Advance(operationBudget, timeBudget);
        Operations += slice.Operations;
        if (slice.Status == CaseWorkStatus.Completed)
        {
            cached = work.Result;
            work.Dispose();
            work = null;
        }
        else if (slice.Status is CaseWorkStatus.Faulted or CaseWorkStatus.BudgetExhausted or CaseWorkStatus.Cancelled)
            throw new InvalidOperationException("Strategy computation failed: " + slice.Error);
    }

    public IReadOnlyList<CaseStrategyChoice>? Finish(double now)
    {
        if (!active || now < due || work is not null || owner.IsUpdating || revision != owner.KnowledgeRevision) return null;
        active = false;
        return cached;
    }

    public void Cancel() { work?.Dispose(); work=null; active=false; }

    public void Dispose() { work?.Dispose(); work = null; active = false; }
}
