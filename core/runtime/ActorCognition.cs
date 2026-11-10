using System.Text.Json;
using DuelView.Core;

namespace DuelView.Runtime;

internal sealed class ActorCognition
{
    private sealed record Input(string Id,FieldKey Key,JsonElement Value,CaseLiteral Literal);
    private sealed record Query(string Id,string Label,FieldKey Key,CaseLiteral Literal);
    private readonly string actor;
    private readonly CaseTheory theory;
    private readonly string scope;
    private readonly Input[] inputs;
    private readonly Query[] queries;
    private readonly int maxNodes;
    private readonly int maxMatches;
    internal IEnumerable<FieldKey> Outputs=>queries.Select(query=>query.Key);

    internal ActorCognition(string actor,JsonElement declaration)
    {
        this.actor=actor;
        theory=CaseTheory.FromData(declaration.Get("theory"));
        scope=declaration.Get("scope").Text();
        if(theory.Scopes.Count!=1||!theory.Scopes.TryGetValue(scope,out var mind)||mind.Axioms.Count!=0)
            throw new InvalidDataException("认知理论必须是无作者事实的单一主观作用域。");
        static CaseLiteral Literal(JsonElement value)=>value.Deserialize<CaseLiteral>(new JsonSerializerOptions{PropertyNameCaseInsensitive=true})
            ??throw new InvalidDataException("认知映射缺少命题。");
        inputs=declaration.Get("inputs").Items().Select(input=>new Input(input.Get("id").Text(),FieldKey.Read(input.Get("ref"),actor),input.Get("value"),Literal(input.Get("literal")))).ToArray();
        queries=declaration.Get("queries").Items().Select(query=>new Query(query.Get("id").Text(),query.Get("label").Text(),FieldKey.Read(query.Get("ref"),actor),Literal(query.Get("literal")))).ToArray();
        maxNodes=(int)declaration.Get("max_nodes").Number(2048);
        maxMatches=(int)declaration.Get("max_matches").Number(100000);
        if(inputs.Any(input=>input.Id.Length==0||input.Key.Facet=="infer"||input.Value.ValueKind==JsonValueKind.Undefined||!CaseProofChecker.ValidLiteral(input.Literal,true))||
           queries.Any(query=>query.Id.Length==0||query.Key.Facet!="infer"||!CaseProofChecker.ValidLiteral(query.Literal,true))||
           inputs.Select(input=>input.Id).Distinct().Count()!=inputs.Length||queries.Select(query=>query.Key).Distinct().Count()!=queries.Length||
           queries.Select(query=>query.Id).Distinct().Count()!=queries.Length||maxNodes is <1 or >10000||maxMatches<1)
            throw new InvalidDataException("认知输入、输出或预算不合法。");
    }

    internal bool NeedsRefresh(IReadOnlyDictionary<FieldKey,Fact> writes,Func<FieldKey,Fact?> before)=>
        queries.Any(query=>before(query.Key) is not {Known:true})||inputs.Any(input=>writes.TryGetValue(input.Key,out var next)&&
            (before(input.Key) is not {} old||old.Known!=next.Known||old.Conflicted!=next.Conflicted||old.Confidence!=next.Confidence||!Values.Same(old.Value,next.Value)));

    internal Work Begin(Func<FieldKey,Fact?> read,IEnumerable<Evidence> evidence)
    {
        var history=evidence.ToLookup(item=>item.Key);
        var axioms=new List<CaseAxiom>();
        var confidence=new Dictionary<string,double>();
        foreach(var input in inputs)
        {
            if(read(input.Key) is not {Known:true} fact)continue;
            var sources=history[input.Key].Where(item=>item.Method!="inference"&&item.Time==fact.ObservedAt&&item.Confidence==fact.Confidence&&Values.Same(item.Value,input.Value)).ToArray();
            if(fact.Conflicted?sources.Length==0:!Values.Same(fact.Value,input.Value))continue;
            axioms.Add(new(input.Id,input.Literal,JsonSerializer.Serialize(new {actor,key=input.Key,value=input.Value,confidence=fact.Confidence,
                observed_at=fact.ObservedAt,origin=sources.Length==0?"initial_belief":"subjective_evidence",evidence_ids=sources.Select(item=>item.Id).ToArray()})));
            confidence[input.Id]=fact.Confidence;
        }
        var grounded=theory.WithEvidence(scope,axioms);
        return new(this,grounded,new CaseInferenceWork(grounded.Scopes[scope],maxNodes,maxMatches),confidence);
    }

    internal sealed class Work(ActorCognition owner,CaseTheory grounded,CaseInferenceWork inference,Dictionary<string,double> confidence):IDisposable
    {
        internal bool Advance(int budget)
        {
            var slice=inference.Advance(Math.Max(32,budget*32),TimeSpan.FromMilliseconds(2));
            if(slice.Status is CaseWorkStatus.BudgetExhausted or CaseWorkStatus.Faulted)
                throw new InvalidDataException("主观认知演算未完成："+slice.Error);
            return slice.Status==CaseWorkStatus.Completed;
        }

        internal IEnumerable<(FieldKey Key,Fact Fact,Evidence Evidence)> Results(double time)
        {
            foreach(var query in owner.queries)
            {
                var result=grounded.ClassifyProof(owner.scope,query.Literal,inference.Result);
                var certainty=(result.Support?.Axioms??[]).Concat(result.Refutation?.Axioms??[]).Select(id=>confidence[id]).DefaultIfEmpty(1).Min();
                var value=JsonSerializer.SerializeToElement(result.Status);
                var source=JsonSerializer.SerializeToElement(new {actor=owner.actor,rule="cognition/"+query.Id,label=query.Label,
                    scope=owner.scope,query=query.Literal,status=result.Status,support=result.Support,refutation=result.Refutation,
                    premises=grounded.Scopes[owner.scope].Axioms.Where(axiom=>(result.Support?.Axioms??[]).Contains(axiom.Id)||(result.Refutation?.Axioms??[]).Contains(axiom.Id)).Select(axiom=>
                    {
                        var provenance=JsonSerializer.Deserialize<JsonElement>(axiom.Source);
                        return new {axiom.Id,axiom.Literal,key=provenance.Get("key"),evidence_ids=provenance.Get("evidence_ids"),origin=provenance.Get("origin"),observed_at=provenance.Get("observed_at"),confidence=provenance.Get("confidence")};
                    })});
                yield return (query.Key,new Fact(value,true,false,certainty,time,0),new Evidence("cognition/"+owner.actor+"/"+query.Id+"/"+time.ToString("R",System.Globalization.CultureInfo.InvariantCulture),query.Key,value,certainty,time,"inference",source));
            }
        }
        public void Dispose()=>inference.Dispose();
    }
}
