using System.Text.Json;
using DuelView.Core;

namespace DuelView.Runtime;

public sealed record MechanicReceipt(double Time,long Execution,string Actor,string Action,string Kind,bool Success,JsonElement Details);
public sealed record IncantationLease(FieldKey Field,Fact Before,JsonElement Applied,double Expires,string Actor,string Action,string[] Witnesses);
public sealed record MechanicsCheckpoint(MechanicReceipt[] History,IncantationLease[] Leases,string[] FiredEvents,Dictionary<long,string[]> DeductionSelections);

/// <summary>Deliberate cognition, persuasion and word magic belong to the same session
/// transaction as ordinary actions. None of these evaluators calls the daily drive scorer.</summary>
public sealed partial class RuntimeSession
{
    private sealed record DeductionEvidence(string Id,string Label,Condition Condition);
    private sealed record InlineDeduction(string Actor,JsonElement Declaration,CaseTheory Theory,CaseLiteral Conclusion,DeductionEvidence[] Evidence,Dictionary<FieldKey,JsonElement> Learns);
    private sealed record WorldEvent(string Id,double At,Condition Condition,Dictionary<FieldKey,JsonElement> Writes,string[] Witnesses,string Label);
    private readonly Dictionary<string,InlineDeduction> inlineDeductions=new(StringComparer.Ordinal);
    private readonly Dictionary<long,string[]> deductionSelections=[];
    private readonly Dictionary<FieldKey,IncantationLease> incantationLeases=[];
    private readonly List<WorldEvent> worldEvents=[];
    private readonly HashSet<string> firedWorldEvents=new(StringComparer.Ordinal);
    private readonly List<MechanicReceipt> mechanicHistory=[];
    public IReadOnlyList<MechanicReceipt> MechanicHistory=>mechanicHistory.AsReadOnly();
    public IReadOnlyList<MechanicReceipt> MechanicHistoryFor(string actor)
    {
        if(!actors.TryGetValue(actor,out var client))throw new ArgumentException("Unknown observing actor.",nameof(actor));
        var witnessed=client.Evidence.Select(item=>item.Source.Get("id").Text()).Where(id=>id.Length>0).ToHashSet(StringComparer.Ordinal);
        return mechanicHistory.Where(item=>item.Actor==actor||item.Actor=="world"&&item.Kind=="world_event"&&witnessed.Contains(item.Action))
            .Select(item=>item with {Details=ProjectMechanicDetails(item.Kind,item.Details,actor)}).ToArray();
    }
    public static JsonElement ProjectMechanicDetails(string kind,JsonElement details,string viewer)
    {
        if(kind!="suggestion"||details.ValueKind!=JsonValueKind.Object||details.Get("target").Text()==viewer)return details;
        string[] privateFields=["score","threshold","contributions","context"];
        return JsonSerializer.SerializeToElement(details.EnumerateObject().Where(field=>!privateFields.Contains(field.Name,StringComparer.Ordinal))
            .ToDictionary(field=>field.Name,field=>field.Value.Clone(),StringComparer.Ordinal));
    }
    public object? LastOpinion { get; private set; }
    public object? LastIncantation { get; private set; }

    internal static FieldKey PathKey(string path)
    {
        var last=path.LastIndexOf('.');
        if(last<=0||last==path.Length-1)throw new InvalidDataException("Expected object[.facet].field: "+path);
        var prefix=path[..last];var facet=prefix.LastIndexOf('.');
        var explicitFacet=facet>0&&prefix[(facet+1)..] is "state" or "phys" or "trace" or "lock" or "doc" or "infer";
        return new(explicitFacet?prefix[..facet]:prefix,explicitFacet?prefix[(facet+1)..]:"state",path[(last+1)..]);
    }
    private static Condition CompactCondition(JsonElement value,string actor)
    {
        if(value.Get("op").ValueKind==JsonValueKind.String)return Condition.Compile(value,actor);
        return new Condition.All(value.Fields().Select(field=>(Condition)new Condition.EqualsValue(PathKey(field.Name),field.Value.Clone())).ToArray());
    }
    private static Dictionary<FieldKey,JsonElement> FieldValues(JsonElement value)=>value.Fields().ToDictionary(field=>PathKey(field.Name),field=>field.Value.Clone());
    private static bool EvidenceKnown(DeductionEvidence evidence,ActorClient actor)=>
        evidence.Condition.Evaluate(actor.Recall)==Truth.True&&evidence.Condition.Inputs.All(key=>actor.Recall(key) is {Known:true,Conflicted:false});
    private static CaseLiteral Token(string value)
    {
        if(string.IsNullOrWhiteSpace(value))throw new InvalidDataException("Reasoning requires a named proposition.");
        return new("case_fact",new[]{value.StartsWith("not:",StringComparison.Ordinal)?value[4..]:value},value.StartsWith("not:",StringComparison.Ordinal));
    }
    private static object LiteralData(CaseLiteral literal)=>new {predicate=literal.Predicate,args=literal.Args,negative=literal.Negative};
    private void RecordMechanic(Decision decision,string kind,bool success,object details)
    {
        var data=JsonSerializer.SerializeToElement(details);
        mechanicHistory.Add(new(ContentTime,decision.Execution,decision.Actor,decision.Action.Id,kind,success,data));
    }
    private static double Finite(JsonElement value,double fallback,string label)
    {
        var number=value.Number(fallback);
        if(!double.IsFinite(number))throw new InvalidDataException("Invalid finite "+label);
        return number;
    }

    public void ConfigureMechanics(JsonElement declaration)
    {
        foreach(var actor in actors.Values)
        {
            var opinion=actor.Declaration.Get("opinion");
            foreach(var field in new[]{"base_trust","threshold","evidence_weight","cost_aversion","risk_aversion"})
                if(opinion.Get(field).ValueKind!=JsonValueKind.Undefined)_=Finite(opinion.Get(field),0,"opinion "+field);
            foreach(var value in opinion.Get("values").Fields())_=Finite(value.Value,0,"opinion value");
            foreach(var value in opinion.Get("trust").Fields())_=Finite(value.Value,0,"opinion trust");
            foreach(var modifier in opinion.Get("modifiers").Items())
            {
                var speaker=modifier.Get("speaker");
                if(speaker.ValueKind!=JsonValueKind.Undefined&&(speaker.ValueKind!=JsonValueKind.String||!actors.ContainsKey(speaker.Text())))
                    throw new InvalidDataException("Opinion modifier speaker must identify an existing actor: "+actor.Id);
                _=CompactCondition(modifier.Get("when"),actor.Id);_=Finite(modifier.Get("score"),0,"opinion modifier");
            }
            foreach(var action in actor.Declaration.Get("actions").Items())
            {
                var id=action.Get("id").Text();
                if(action.Get("deduction").ValueKind==JsonValueKind.Object)ConfigureInlineDeduction(actor.Id,id,action.Get("deduction"));
                if(action.Get("strategy").ValueKind==JsonValueKind.Object)ConfigureInlineStrategy(actor,id,action.Get("strategy"));
                if(action.Get("suggestion").ValueKind==JsonValueKind.Object)
                {
                    var suggestion=action.Get("suggestion");var target=suggestion.Get("target").Text();
                    if(!actors.ContainsKey(target)||target==actor.Id||actors[target].Declaration.Get("opinion").ValueKind!=JsonValueKind.Object)
                        throw new InvalidDataException("Suggestion needs another actor with an independent opinion profile: "+id);
                    if(suggestion.Get("result").Text().Length==0)throw new InvalidDataException("Suggestion needs an observable result: "+id);
                    _=PathKey(suggestion.Get("result").Text());
                    foreach(var path in suggestion.Get("evidence").Items())_=PathKey(path.Text());
                    foreach(var appeal in suggestion.Get("appeal").Fields())
                        if(Math.Abs(Finite(appeal.Value,0,"opinion appeal"))>1)throw new InvalidDataException("Each appeal must be within -1 and 1: "+id);
                    foreach(var field in new[]{"cost","risk"})if(Finite(suggestion.Get(field),0,"suggestion "+field) is <0 or >1)
                        throw new InvalidDataException("Suggestion cost and risk must be within 0 and 1: "+id);
                }
                if(action.Get("incantation").ValueKind==JsonValueKind.Object)
                {
                    var magic=action.Get("incantation");var rule=magic.Get("rule");
                    if(magic.Get("formula").Text().Length==0||!magic.Get("requires").Fields().Any()||magic.Get("cost").Number()<=0||
                        magic.Get("backlash").Get("amount").Number()<=0||rule.Get("duration_minutes").Number()<=0)
                        throw new InvalidDataException("Incantation needs a formula, cognition, positive cost, backlash and duration: "+id);
                    var paths=new[]{magic.Get("resource").Text(),magic.Get("backlash").Get("field").Text(),rule.Get("field").Text()};
                    if(paths.Select(PathKey).Distinct().Count()!=3||rule.Get("value").ValueKind==JsonValueKind.Undefined)throw new InvalidDataException("Word magic resource, backlash and rule fields must be distinct: "+id);
                    foreach(var path in paths)
                        if(World.Read(PathKey(path)) is not {Known:true,Conflicted:false})throw new InvalidDataException("Incantation field requires a declared initial value: "+path);
                    _=Finite(World.Read(PathKey(paths[0]))!.Value,double.NaN,"incantation resource");
                    _=Finite(World.Read(PathKey(paths[1]))!.Value,double.NaN,"incantation backlash state");
                    _=Finite(magic.Get("cost"),0,"incantation cost");
                    _=Finite(magic.Get("backlash").Get("amount"),0,"incantation backlash");
                    _=Finite(rule.Get("duration_minutes"),0,"incantation duration");
                    foreach(var witness in magic.Get("witnesses").Items())if(!actors.ContainsKey(witness.Text()))throw new InvalidDataException("Unknown incantation witness.");
                    _=CompactCondition(magic.Get("requires"),actor.Id);
                }
            }
        }
        foreach(var data in declaration.Get("world_events").Items())
        {
            var id=data.Get("id").Text();var at=Finite(data.Get("at_game_minutes"),0,"world event time");
            var witnesses=data.Get("tell").Items().Select(value=>value.Text()).ToArray();
            if(id.Length==0||at<0||worldEvents.Any(item=>item.Id==id)||witnesses.Any(witness=>!actors.ContainsKey(witness)))throw new InvalidDataException("Invalid world event.");
            var gates=new List<Condition>{CompactCondition(data.Get("when"),"world")};
            if(data.Get("when_condition").ValueKind==JsonValueKind.Object)gates.Add(Condition.Compile(data.Get("when_condition"),"world"));
            worldEvents.Add(new(id,at,new Condition.All(gates),FieldValues(data.Get("writes")),witnesses,data.Get("label").Text(id)));
        }
    }

    private void ConfigureInlineDeduction(string actor,string action,JsonElement declaration)
    {
        var evidence=declaration.Get("evidence").Items().Select(item=>new DeductionEvidence(item.Get("id").Text(),item.Get("label").Text(item.Get("id").Text()),CompactCondition(item.Get("when"),actor))).ToArray();
        var rules=declaration.Get("rules").Items().ToArray();var conclusion=Token(declaration.Get("conclusion").Text());
        var learns=FieldValues(declaration.Get("learns"));
        if(evidence.Length<2||evidence.Length>32||evidence.Any(item=>item.Id.Length==0||!item.Condition.Inputs.Any())||evidence.Select(item=>item.Id).Distinct().Count()!=evidence.Length||rules.Length==0||rules.Length>32||learns.Count==0)
            throw new InvalidDataException("Deliberate deduction requires distinct sourced evidence, inference rules and a cognitive result: "+action);
        foreach(var rule in rules)if(!rule.Get("all").Items().Any())throw new InvalidDataException("A deduction rule cannot assert an ungrounded conclusion: "+action);
        var theory=CaseTheory.FromData(JsonSerializer.SerializeToElement(new {scopes=new[]{new {
            id=actor,axioms=Array.Empty<object>(),
            rules=rules.Select(rule=>new {id=rule.Get("id").Text(),premises=rule.Get("all").Items().Select(item=>LiteralData(Token(item.Text()))).ToArray(),
                conclusion=LiteralData(Token(rule.Get("then").Text())),source=rule.Get("label").Text(rule.Get("id").Text())}).ToArray(),
            theorems=new[]{new {id="deduction_goal",conclusion=LiteralData(conclusion)}} }}}));
        if(!inlineDeductions.TryAdd(action,new(actor,declaration.Clone(),theory,conclusion,evidence,learns)))throw new InvalidDataException("Duplicate deduction action.");
    }

    public object DeductionPreview(string actor,string action)
    {
        if(!inlineDeductions.TryGetValue(action,out var deduction)||deduction.Actor!=actor)throw new InvalidOperationException("No deliberate deduction belongs to this action.");
        var client=actors[actor];
        return new {action,title=deduction.Declaration.Get("title").Text(),knowledge_revision=client.KnowledgeRevision,
            evidence=deduction.Evidence.Select(item=>{var known=EvidenceKnown(item,client);return new {id=item.Id,label=known?item.Label:"尚未确认的线索",known,
                source_ids=known?client.Evidence.Where(source=>item.Condition.Inputs.Contains(source.Key)).Select(source=>source.Id).Distinct().ToArray():Array.Empty<string>(),
                fields=known?item.Condition.Inputs.ToArray():Array.Empty<FieldKey>(),
                values=item.Condition.Inputs.Where(_=>known).Select(key=>new {key,value=client.Recall(key)!.Value,confidence=client.Recall(key)!.Confidence}).ToArray()};}).ToArray(),
            rules=deduction.Declaration.Get("rules").Items().Select(rule=>new {id=rule.Get("id").Text(),label=rule.Get("label").Text(),
                premises=rule.Get("all").Items().Select(item=>item.Text()).ToArray(),conclusion=rule.Get("then").Text()}).ToArray(),
            conclusion=deduction.Declaration.Get("conclusion").Text(),qualification=deduction.Declaration.Get("qualification").Text()};
    }

    public Decision SubmitDeduction(string actor,string action,string[] evidenceIds)
    {
        if(!inlineDeductions.TryGetValue(action,out var deduction)||deduction.Actor!=actor||evidenceIds is null||evidenceIds.Length>32||evidenceIds.Distinct(StringComparer.Ordinal).Count()!=evidenceIds.Length)
            throw new InvalidOperationException("Invalid evidence selection for this deduction.");
        foreach(var id in evidenceIds)
            if(deduction.Evidence.SingleOrDefault(item=>item.Id==id) is not { } evidence||!EvidenceKnown(evidence,actors[actor]))
                throw new InvalidOperationException("Only currently observed evidence can be selected.");
        var decision=Submit(actor,action);
        deductionSelections.Add(decision.Execution,evidenceIds.ToArray());
        return decision;
    }

    private bool EvaluateInlineDeduction(Decision decision,List<Observation> feedback)
    {
        var deduction=inlineDeductions[decision.Action.Id];var client=actors[decision.Actor];
        var selected=deductionSelections.GetValueOrDefault(decision.Execution)?.ToHashSet(StringComparer.Ordinal);
        var axioms=new List<CaseAxiom>();var evidenceDetails=new List<object>();
        foreach(var item in deduction.Evidence)
        {
            if(selected is not null&&!selected.Contains(item.Id)||!EvidenceKnown(item,client))continue;
            var sources=client.Evidence.Where(source=>item.Condition.Inputs.Contains(source.Key)).Select(source=>source.Id).Distinct().ToArray();
            var provenance=new {actor=client.Id,evidence=item.Id,source_ids=sources,fields=item.Condition.Inputs.ToArray(),origin=sources.Length==0?"initial_memory":"observed_memory"};
            axioms.Add(new("observed/"+item.Id,Token(item.Id),JsonSerializer.Serialize(provenance)));
            evidenceDetails.Add(new {id=item.Id,label=item.Label,source_ids=sources,fields=item.Condition.Inputs.ToArray()});
        }
        var theory=deduction.Theory.WithEvidence(client.Id,axioms);
        var proof=theory.Prove(client.Id,deduction.Conclusion,2048,100000);
        var succeeded=proof.Status=="proved"&&proof.Support is {Rules.Count:>0};
        var details=new {actor=client.Id,action=decision.Action.Id,title=deduction.Declaration.Get("title").Text(),knowledge_revision=client.KnowledgeRevision,
            status=proof.Status,selected_evidence=selected?.ToArray()??axioms.Select(item=>item.Id[9..]).ToArray(),evidence=evidenceDetails.ToArray(),
            conclusion=deduction.Declaration.Get("conclusion").Text(),support=proof.Support,refutation=proof.Refutation,
            qualification=deduction.Declaration.Get("qualification").Text(),
            learned=succeeded?deduction.Learns.Keys.ToArray():Array.Empty<FieldKey>()};
        LastDeduction=JsonSerializer.SerializeToElement(details);RecordMechanic(decision,"deduction",succeeded,details);
        if(succeeded)foreach(var (key,value) in deduction.Learns)
            feedback.Add(new("proof/"+(++nextEvidence),key,value,1,ContentTime,InformationOrigin.ActionFeedback,JsonSerializer.SerializeToElement(new {
                actor=client.Id,action=decision.Action.Id,query=deduction.Declaration.Get("conclusion").Text(),support=proof.Support,
                evidence=axioms.Select(item=>item.Id).ToArray()})));
        return succeeded;
    }

    private void ConfigureInlineStrategy(ActorClient actor,string action,JsonElement declaration)
    {
        var options=declaration.Get("options").Items().ToArray();var mappings=new List<object>();var rules=new List<object>();var choices=new List<object>();
        var values=declaration.Get("values");var hasValues=values.ValueKind==JsonValueKind.Object&&values.EnumerateObject().Any();
        if(options.Length==0||options.Length>16)throw new InvalidDataException("Strategy requires bounded alternatives.");
        foreach(var option in options)
        {
            var id=option.Get("id").Text();var requirements=new List<object>();var index=0;
            foreach(var condition in option.Get("when").Fields())
            {
                var key=PathKey(condition.Name);var literal=Token(id+"/evidence/"+(++index));requirements.Add(LiteralData(literal));
                mappings.Add(new {actor=actor.Id,id=action+"/"+id+"/"+index,reference=new {type="ref",@object=key.Object,facet=key.Facet,field=key.Field},equals=condition.Value,literal=LiteralData(literal)});
            }
            if(requirements.Count==0)throw new InvalidDataException("Strategy alternative requires subjective evidence: "+id);
            var ready=LiteralData(Token(id+"/ready"));var basis=option.Get("basis").Text(option.Get("label").Text(id));
            rules.Add(new {id="ready/"+id,premises=requirements.ToArray(),conclusion=ready,source=basis});
            choices.Add(new {action=id,basis=new[]{basis},requires=new[]{ready},prohibits=Array.Empty<object>(),
                promotes=hasValues?option.Get("promotes"):JsonSerializer.SerializeToElement(new {authored_utility=Finite(option.Get("utility"),0,"strategy utility")})});
        }
        var theory=CaseTheory.FromData(JsonSerializer.SerializeToElement(new {scopes=new[]{new {id=actor.Id,axioms=Array.Empty<object>(),rules=rules.ToArray(),theorems=Array.Empty<object>()}}}));
        var profile=JsonSerializer.SerializeToElement(new {actor=actor.Id,basis=new[]{declaration.Get("basis").Text("DV声明的人物目的与可行方案")},
            drives=hasValues?values:JsonSerializer.SerializeToElement(new {authored_utility=1}),choices=choices.ToArray()});
        var completion=declaration.Get("completion_output").Text();
        var binding=new StrategyBinding(actor.Id,new StrategyActivity(actor,theory,profile,JsonSerializer.SerializeToElement(mappings),contentTimeUnit),
            PathKey(declaration.Get("output").Text()),completion.Length>0?PathKey(completion):null,declaration.Get("publish").Flag());
        if(!strategyBindings.TryAdd(action,binding))throw new InvalidDataException("Duplicate strategy activity.");
    }

    private bool MechanicEligible(string actor,ActionCandidate action)
    {
        var magic=action.Declaration.Get("incantation");if(magic.ValueKind!=JsonValueKind.Object)return true;
        if(CompactCondition(magic.Get("requires"),actor).Evaluate(actors[actor].Recall)!=Truth.True)return false;
        var resource=actors[actor].Recall(PathKey(magic.Get("resource").Text()));
        return resource is {Known:true,Conflicted:false}&&resource.Value.Number(double.NegativeInfinity)>=magic.Get("cost").Number();
    }
    private IEnumerable<FieldKey> MechanicFocus(ActionCandidate action)
    {
        if(inlineDeductions.TryGetValue(action.Id,out var deduction))foreach(var key in deduction.Learns.Keys)yield return key;
        var suggestion=action.Declaration.Get("suggestion");
        if(suggestion.ValueKind==JsonValueKind.Object)yield return PathKey(suggestion.Get("result").Text());
        var magic=action.Declaration.Get("incantation");
        if(magic.ValueKind==JsonValueKind.Object)
        {yield return PathKey(magic.Get("resource").Text());yield return PathKey(magic.Get("backlash").Get("field").Text());yield return PathKey(magic.Get("rule").Get("field").Text());}
    }

    private bool EvaluateSuggestion(Decision decision,Dictionary<FieldKey,Fact> writes,List<Observation> feedback,List<FieldChange> changes)
    {
        var proposal=decision.Action.Declaration.Get("suggestion");var speaker=actors[decision.Actor];var target=actors[proposal.Get("target").Text()];
        var profile=target.Declaration.Get("opinion");var evidenceKeys=proposal.Get("evidence").Items().Select(item=>PathKey(item.Text())).Distinct().ToArray();
        var supplied=evidenceKeys.Where(key=>speaker.Recall(key) is {Known:true,Conflicted:false}).ToArray();
        string[] EvidenceFor(FieldKey field)=>speaker.Evidence.Where(item=>item.Key==field&&speaker.Recall(field) is {Known:true} known&&
            Values.Same(item.Value,known.Value)&&item.Time==known.ObservedAt&&item.Confidence==known.Confidence).Select(item=>item.Id).Distinct().ToArray();
        var shared=supplied.ToDictionary(key=>key,key=>speaker.Recall(key)!);
        Fact? TargetRead(FieldKey key)=>target.Recall(key)??shared.GetValueOrDefault(key);
        var contributions=new Dictionary<string,double>(StringComparer.Ordinal) {
            ["trust"]=profile.Get("trust").Get(speaker.Id).Number(profile.Get("base_trust").Number()),
            ["evidence"]=profile.Get("evidence_weight").Number(.4)*supplied.Length,
            ["cost"]=-profile.Get("cost_aversion").Number(1)*proposal.Get("cost").Number(),
            ["risk"]=-profile.Get("risk_aversion").Number(1)*proposal.Get("risk").Number()};
        foreach(var appeal in proposal.Get("appeal").Fields())contributions["value:"+appeal.Name]=profile.Get("values").Get(appeal.Name).Number()*appeal.Value.Number();
        var reasons=new List<string>();var index=0;
        foreach(var modifier in profile.Get("modifiers").Items())if((modifier.Get("speaker").ValueKind==JsonValueKind.Undefined||modifier.Get("speaker").Text()==speaker.Id)&&CompactCondition(modifier.Get("when"),target.Id).Evaluate(TargetRead)==Truth.True)
        {contributions["context:"+(++index)]=modifier.Get("score").Number();reasons.Add(modifier.Get("reason").Text());}
        var threshold=profile.Get("threshold").Number(1);var score=contributions.Values.Sum();
        var missing=evidenceKeys.Except(supplied).ToArray();var accepted=missing.Length==0&&score>=threshold;
        var key=PathKey(proposal.Get("result").Text());var result=new Fact(JsonSerializer.SerializeToElement(accepted),true,false,1,ContentTime,0);
        if(accepted)writes[key]=result;
        else {var rejected=World.Apply(new Dictionary<FieldKey,Fact>{{key,result}});changes.AddRange(rejected);Rules.Changed(rejected);}
        var details=new {actor=speaker.Id,target=target.Id,action=decision.Action.Id,execution=decision.Execution,accepted,score,threshold,contributions,context=reasons.ToArray(),
            physical_field=key,world_revision=accepted?(long?)null:World.Read(key)?.Revision,
            evidence=supplied.Select(key=>new {key,value=speaker.Recall(key)!.Value,source_ids=EvidenceFor(key)}).ToArray(),missing,
            reason=missing.Length>0?"evidence_missing":accepted?"independent_opinion_accepted":"independent_opinion_rejected"};
        LastOpinion=JsonSerializer.SerializeToElement(details);RecordMechanic(decision,"suggestion",accepted,details);
        var source=JsonSerializer.SerializeToElement(details);
        feedback.Add(new("opinion/"+(++nextEvidence),key,result.Value,1,ContentTime,InformationOrigin.ActionFeedback,ProjectMechanicDetails("suggestion",source,speaker.Id)));
        SendKnowledge(target.Id,key,result.Value,source);
        foreach(var evidence in supplied)SendKnowledge(target.Id,evidence,speaker.Recall(evidence)!.Value,JsonSerializer.SerializeToElement(new {
            actor=speaker.Id,recipient=target.Id,action=decision.Action.Id,execution=decision.Execution,source_ids=EvidenceFor(evidence)}));
        return accepted;
    }

    private bool EvaluateIncantation(Decision decision,Dictionary<FieldKey,Fact> writes,List<Observation> feedback)
    {
        if(!MechanicEligible(decision.Actor,decision.Action))return false;
        var magic=decision.Action.Declaration.Get("incantation");var rule=magic.Get("rule");
        var resource=PathKey(magic.Get("resource").Text());var backlash=PathKey(magic.Get("backlash").Get("field").Text());var target=PathKey(rule.Get("field").Text());
        if(World.Read(resource) is not {Known:true,Conflicted:false} available||available.Value.Number(double.NegativeInfinity)<magic.Get("cost").Number())return false;
        var before=World.Read(target)!;var previous=incantationLeases.TryGetValue(target,out var active)?active.Before:before;
        var cost=magic.Get("cost").Number();var harm=magic.Get("backlash").Get("amount").Number();
        var expires=ContentTime+rule.Get("duration_minutes").Number();var applied=rule.Get("value").Clone();
        if(writes.ContainsKey(resource)||writes.ContainsKey(backlash)||writes.ContainsKey(target))throw new InvalidDataException("Word magic owns its resource and rule effects.");
        writes[resource]=new(JsonSerializer.SerializeToElement(World.Read(resource)!.Value.Number()-cost),true,false,1,ContentTime,0);
        writes[backlash]=new(JsonSerializer.SerializeToElement(World.Read(backlash)!.Value.Number()+harm),true,false,1,ContentTime,0);
        writes[target]=new(applied,true,false,1,ContentTime,0);
        var witnesses=magic.Get("witnesses").Items().Select(item=>item.Text()).Append(decision.Actor).Distinct().ToArray();
        incantationLeases[target]=new(target,previous,applied,expires,decision.Actor,decision.Action.Id,witnesses);
        var details=new {actor=decision.Actor,action=decision.Action.Id,execution=decision.Execution,formula=magic.Get("formula").Text(),cost,resource,resource_remaining=writes[resource].Value,
            backlash=new {field=backlash,amount=harm,total=writes[backlash].Value},rule=new {field=target,before=before.Value,value=applied},expires,knowledge_revision=actors[decision.Actor].KnowledgeRevision};
        LastIncantation=JsonSerializer.SerializeToElement(details);RecordMechanic(decision,"incantation",true,details);
        var source=JsonSerializer.SerializeToElement(details);
        foreach(var key in new[]{resource,backlash,target})feedback.Add(new("incantation/"+(++nextEvidence),key,writes[key].Value,1,ContentTime,InformationOrigin.ActionFeedback,source));
        foreach(var witness in witnesses.Where(id=>id!=decision.Actor))SendKnowledge(witness,target,applied,source);
        return true;
    }

    private void SendKnowledge(string actor,FieldKey key,JsonElement value,JsonElement source)
    {
        actors[actor].ReceiveDirected(new("mechanic/"+(++nextEvidence),key,value.Clone(),1,ContentTime,InformationOrigin.Communication,source));
    }
    private void AdvanceMechanics()
    {
        foreach(var lease in incantationLeases.Values.Where(item=>item.Expires<=ContentTime).ToArray())
        {
            // A later physical repair can supersede a temporary semantic rule.
            if(World.Read(lease.Field) is { } current&&Values.Same(current.Value,lease.Applied))
            {
                Rules.Changed(World.Apply(new Dictionary<FieldKey,Fact>{{lease.Field,lease.Before with {ObservedAt=ContentTime}}}));
                var details=JsonSerializer.SerializeToElement(new {actor=lease.Actor,action=lease.Action,field=lease.Field,value=lease.Before.Value,expired_at=ContentTime});
                foreach(var witness in lease.Witnesses)SendKnowledge(witness,lease.Field,lease.Before.Value,details);
                mechanicHistory.Add(new(ContentTime,0,lease.Actor,lease.Action,"incantation_expired",true,details));
            }
            incantationLeases.Remove(lease.Field);
        }
        foreach(var item in worldEvents)
        {
            if(firedWorldEvents.Contains(item.Id)||ContentTime<item.At||item.Condition.Evaluate(World.Read)!=Truth.True)continue;
            var writes=item.Writes.ToDictionary(pair=>pair.Key,pair=>new Fact(pair.Value,true,false,1,ContentTime,0));
            Rules.Changed(World.Apply(writes));firedWorldEvents.Add(item.Id);
            var details=JsonSerializer.SerializeToElement(new {id=item.Id,label=item.Label,time=ContentTime});
            foreach(var actor in item.Witnesses)foreach(var (key,value) in item.Writes)SendKnowledge(actor,key,value,details);
            mechanicHistory.Add(new(ContentTime,0,"world",item.Id,"world_event",true,details));
        }
    }
    private double NextMechanicTime()=>incantationLeases.Values.Select(item=>item.Expires*contentTimeUnit)
        .Concat(worldEvents.Where(item=>!firedWorldEvents.Contains(item.Id)&&item.At>ContentTime).Select(item=>item.At*contentTimeUnit))
        .DefaultIfEmpty(double.PositiveInfinity).Min();
    private MechanicsCheckpoint SaveMechanics()=>new(mechanicHistory.ToArray(),incantationLeases.Values.ToArray(),firedWorldEvents.ToArray(),deductionSelections.ToDictionary(item=>item.Key,item=>item.Value.ToArray()));
    private void RestoreMechanics(MechanicsCheckpoint? state,HashSet<long> executions)
    {
        mechanicHistory.Clear();incantationLeases.Clear();firedWorldEvents.Clear();deductionSelections.Clear();
        LastDeduction=null;LastOpinion=null;LastIncantation=null;LastStrategy=null;
        if(state is null)return;
        if(state.History is null||state.Leases is null||state.FiredEvents is null||state.DeductionSelections is null||
            state.FiredEvents.Any(id=>worldEvents.All(item=>item.Id!=id))||state.DeductionSelections.Keys.Any(id=>!executions.Contains(id)))throw new InvalidDataException("Invalid mechanics checkpoint.");
        foreach(var receipt in state.History)
        {
            if(!double.IsFinite(receipt.Time)||receipt.Time<0||receipt.Details.ValueKind!=JsonValueKind.Object||receipt.Actor!="world"&&!actors.ContainsKey(receipt.Actor))throw new InvalidDataException("Invalid mechanics receipt.");
            mechanicHistory.Add(receipt);
            if(receipt.Kind=="deduction")LastDeduction=receipt.Details;
            else if(receipt.Kind=="suggestion")LastOpinion=receipt.Details;
            else if(receipt.Kind=="incantation")LastIncantation=receipt.Details;
            else if(receipt.Kind=="strategy")LastStrategy=receipt.Details;
        }
        foreach(var lease in state.Leases)
        {
            if(!double.IsFinite(lease.Expires)||lease.Expires<0||lease.Before is null||lease.Applied.ValueKind==JsonValueKind.Undefined||!actors.ContainsKey(lease.Actor)||lease.Witnesses is null||lease.Witnesses.Any(id=>!actors.ContainsKey(id))||!incantationLeases.TryAdd(lease.Field,lease))
                throw new InvalidDataException("Invalid word magic lease.");
        }
        firedWorldEvents.UnionWith(state.FiredEvents);
        foreach(var (execution,selected) in state.DeductionSelections)
        {
            var decision=DecisionFor(execution);if(selected is null||decision is null||!inlineDeductions.TryGetValue(decision.Action.Id,out var deduction)||selected.Any(id=>deduction.Evidence.All(item=>item.Id!=id)))throw new InvalidDataException("Invalid saved deduction selection.");
            deductionSelections.Add(execution,selected.ToArray());
        }
    }
}
