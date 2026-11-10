using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Encodings.Web;
using System.Text;
using DuelView.Runtime;

// Production text adapter for the same independent Core used by Main.
// Room transitions are timed formal actions; CLI does not claim Godot collision evidence.
internal sealed class NativeCli : IDisposable
{
    const string DefaultContent="assets/data/scenarios/campaign.dv";
    static readonly JsonSerializerOptions Json=new(){Encoder=JavaScriptEncoder.UnsafeRelaxedJsonEscaping};
    readonly CharacterSessionDefinition definition;
    readonly RuntimeSession session;
    readonly JsonElement content;
    readonly string viewer;
    readonly bool automaticViewer;
    readonly AppendAuditLog? log;
    readonly AppendAuditLog? stateLog;
    long stateIndex;
    readonly Dictionary<string,int> completed=[];
    readonly Dictionary<string,double> firstCompletion=[];
    readonly Dictionary<long,Decision> started=[];
    readonly Dictionary<long,DriveEvaluation> decisionDrives=[];
    readonly Dictionary<long,object> decisionReasons=[];
    readonly Dictionary<long,object> decisionAudits=[];
    readonly Dictionary<long,ActionOutcome> actionOutcomes=[];
    readonly Dictionary<string,DriveEvaluation> firstDrives=[];
    readonly Dictionary<string,DecisionOption[]> firstOptions=[];
    readonly List<(string Action,string Slot,double Start,double End)> executions=[];
    readonly List<(string Actor,AffectEvent Event)> affectEvents=[];
    readonly Dictionary<string,int> evidenceCursors=[];
    readonly Dictionary<string,int> evidenceWritten=[];
    readonly HashSet<string> invariantFailures=[];
    readonly List<object> history=[];
    long version;
    int failures;
    int rejectedAttempts;
    int blockedAttempts;
    int successfulActions;
    int recoverableCancellations;
    string? selectedObject;
    readonly double end;
    readonly string? receiptPath;
    bool disposed;
    static JsonElement Get(JsonElement e,string key)=>e.ValueKind==JsonValueKind.Object&&e.TryGetProperty(key,out var v)?v:default;
    static string Text(JsonElement e,string fallback="")=>e.ValueKind==JsonValueKind.String?e.GetString()!:fallback;
    static IEnumerable<JsonElement> Items(JsonElement e)=>e.ValueKind==JsonValueKind.Array?e.EnumerateArray():[];
    static double Num(JsonElement e,double fallback=0)=>e.ValueKind==JsonValueKind.Number?e.GetDouble():fallback;
    static string PathOf(string path)=>Path.GetFullPath(path.Replace("res://",""));
    static FieldKey Key(JsonElement r)=>new(Text(Get(r,"object")),Text(Get(r,"facet")),Text(Get(r,"field")));
    static string Encode(object? value)=>JsonSerializer.Serialize(value,Json);
    static void AppendRecord(AppendAuditLog? destination,Dictionary<string,object?> row,long index)
    {
        if(destination is null)return;
        var buffer=new StringBuilder();var first=true;
        foreach(var pair in row){buffer.Append(first?"- ":"  ").Append(pair.Key).Append(": ").Append(Encode(pair.Value)).Append('\n');first=false;}
        buffer.Append('\n');destination.Append(buffer.ToString(),index);
    }
    object? VisibleMechanic(object? value)
    {
        if(value is null)return null;
        var data=JsonSerializer.SerializeToElement(value);
        return Text(Get(data,"actor"))==viewer?Get(data,"accepted").ValueKind!=JsonValueKind.Undefined?RuntimeSession.ProjectMechanicDetails("suggestion",data,viewer):value:null;
    }
    NativeCli(JsonElement options)
    {
        var path=Text(Get(options,"content_path"),DefaultContent);
        definition=new(File.ReadAllText(PathOf(path)),File.ReadAllText("assets/data/98-runtime-session.data.dv"));
        content=definition.Declaration;
        viewer=Text(Get(options,"viewer"),Text(Get(content,"viewer")));
        if(!Actors.Any(a=>Text(Get(a,"id"))==viewer))throw new InvalidDataException("Unknown viewer.");
        session=definition.Create();
        foreach(var item in Items(Get(content,"deductions")))session.ConfigureDeduction(File.ReadAllText(PathOf(Text(Get(item,"source")))),item);
        foreach(var item in Items(Get(content,"strategy_activities")))session.ConfigureStrategy(File.ReadAllText(PathOf(Text(Get(item,"source")))),item);
        end=Num(Get(Get(content,"run"),"end_minutes"));
        if(end<=session.ContentTime)throw new InvalidDataException("Invalid DV run horizon.");
        automaticViewer=Text(Get(options,"controller"))=="ai";
        if(!automaticViewer)session.SetAutonomy(viewer,false);
        receiptPath=Text(Get(options,"receipt_path"));
        if(receiptPath.Length>0){Directory.CreateDirectory(Path.GetDirectoryName(receiptPath)!);log=new(receiptPath);}
        if(receiptPath.Length>0)stateLog=new(Path.ChangeExtension(receiptPath,"states.yaml"));
    }
    IEnumerable<JsonElement> Actors=>Items(Get(content,"actors"));
    string Room(string actor)=>Text(session.World.Read(new(actor,"state","room"))?.Value??default);
    bool HasCompletion=>Get(content,"completion").ValueKind==JsonValueKind.Object;
    CampaignProgressView Progress=>CampaignProgress.Evaluate(content,session);
    bool CampaignCompleted=>Progress.Completed;
    bool Active=>session.ContentTime<end&&!CampaignCompleted;
    bool Visible(JsonElement fixture)=>Text(Get(fixture,"room"))==Room(viewer)&&Get(fixture,"hidden").ValueKind!=JsonValueKind.True;
    IEnumerable<JsonElement> Actions(string actor)=>Items(Get(Actors.Single(a=>Text(Get(a,"id"))==actor),"actions"));
    object Status()=>new {version,chapter=(int)(session.ContentTime/1440)+1,game_time=session.ContentTime,day=(int)(session.ContentTime/1440)+1,
        status=Active?"running":CampaignCompleted?"completed":"stopped",stop_reason=Active?"":Progress.WindowCompleted?"observation_window_completed":CampaignCompleted?"campaign_completed":"dv_time_horizon",horizon=end,campaign_completed=CampaignCompleted,campaign_progress=Progress};
    bool Check(JsonElement e)
    {
        var absent=Text(Get(e,"action_absent"));
        if(absent.Length>0)return completed.GetValueOrDefault(absent)==0;
        var spread=Get(e,"start_spread");
        if(spread.ValueKind==JsonValueKind.Object)
        {
            var wanted=Items(Get(spread,"actions")).Select(a=>a.GetString()!).ToArray();
            var starts=wanted.Select(id=>executions.Where(x=>x.Action==id).Select(x=>x.Start).DefaultIfEmpty(double.NaN).Min()).ToArray();
            return starts.All(double.IsFinite)&&(starts.Max()-starts.Min())/60>=Num(Get(spread,"minimum_minutes"));
        }
        var countRule=Get(e,"state_event_count");
        if(countRule.ValueKind==JsonValueKind.Object)
        {
            var count=affectEvents.Count(item=>item.Event.Time/60>=Num(Get(e,"from_minutes"))&&item.Event.Time/60<Num(Get(e,"until_minutes"),double.PositiveInfinity)&&item.Event.Kind==Text(Get(countRule,"kind"))&&
                (Text(Get(countRule,"actor")).Length==0||item.Actor==Text(Get(countRule,"actor")))&&
                (Text(Get(countRule,"source")).Length==0||item.Event.Source==Text(Get(countRule,"source"))));
            return count>=Num(Get(countRule,"minimum"))&&count<=Num(Get(countRule,"maximum"),double.PositiveInfinity);
        }
        var sensory=Get(e,"perception_source");
        if(sensory.ValueKind==JsonValueKind.Object)return session.Evidence(Text(Get(sensory,"actor"))).Any(item=>item.Id.StartsWith("perception/",StringComparison.Ordinal)&&
            item.Key.Object==Text(Get(sensory,"object"))&&(Text(Get(sensory,"facet")).Length==0||item.Key.Facet==Text(Get(sensory,"facet")))&&item.Key.Field==Text(Get(sensory,"field"))&&Text(Get(item.Source,"sensor"))==Text(Get(sensory,"sensor")));
        var inference=Get(e,"inference_evidence");
        if(inference.ValueKind==JsonValueKind.Object)return session.Evidence(Text(Get(inference,"actor"))).Any(item=>item.Method=="inference"&&
            item.Key.Object==Text(Get(inference,"object"))&&(Text(Get(inference,"facet")).Length==0||item.Key.Facet==Text(Get(inference,"facet")))&&item.Key.Field==Text(Get(inference,"field"))&&
            Items(Get(item.Source,"premises")).Any()&&Items(Get(item.Source,"premises")).All(p=>Items(Get(p,"evidence_ids")).Any()));
        var provenance=Get(e,"evidence_source");
        if(provenance.ValueKind==JsonValueKind.Object)return session.Evidence(Text(Get(provenance,"actor"))).Any(item=>
            item.Key.Object==Text(Get(provenance,"object"))&&(Text(Get(provenance,"facet")).Length==0||item.Key.Facet==Text(Get(provenance,"facet")))&&item.Key.Field==Text(Get(provenance,"field"))&&Text(Get(item.Source,"action"))==Text(Get(provenance,"action")));
        var competition=Get(e,"drive_competition");
        if(competition.ValueKind==JsonValueKind.Object)
        {
            var chosen=Text(Get(competition,"action"));
            if(!firstOptions.TryGetValue(chosen,out var options))return false;
            var winner=options.FirstOrDefault(o=>o.Action==chosen);
            var other=options.FirstOrDefault(o=>o.Action==Text(Get(competition,"alternative")));
            return winner is not null&&other is not null&&winner.Score>other.Score&&
                winner.Score-winner.Drive.NeedContributions.GetValueOrDefault(Text(Get(competition,"without")))<other.Score;
        }
        var bonus=Get(e,"drive_bonus");
        if(bonus.ValueKind==JsonValueKind.Object)
        {
            if(!firstDrives.TryGetValue(Text(Get(bonus,"action")),out var evaluation))return false;
            var value=evaluation.NeedContributions.GetValueOrDefault(Text(Get(bonus,"key")));
            if(Get(bonus,"required_for_positive_score").ValueKind==JsonValueKind.True&&(evaluation.Score<=0||evaluation.Score-value>0))return false;
            return value>=Num(Get(bonus,"minimum"),double.NegativeInfinity)&&value<=Num(Get(bonus,"maximum"),double.PositiveInfinity);
        }
        var marker=Text(Get(e,"state_event"));
        if(marker.Length>0)return affectEvents.Any(item=>item.Actor==Text(Get(e,"actor"))&&item.Event.Kind==marker&&item.Event.Source==Text(Get(e,"source_action")));
        var before=Text(Get(e,"before"));var after=Text(Get(e,"after"));
        if(before.Length>0)return firstCompletion.TryGetValue(before,out var b)&&firstCompletion.TryGetValue(after,out var a)&&b<a;
        var actor=Text(Get(e,"actor"));
        if(actor.Length>0)return Condition.Compile(Get(e,"condition"),actor).Evaluate(k=>session.View(actor).Knowledge.GetValueOrDefault(k))==Truth.True;
        var action=Text(Get(e,"action"));
        if(action.Length>0)return executions.Count(item=>item.Action==action&&item.End/60>=Num(Get(e,"from_minutes"))&&
            item.End/60<Num(Get(e,"until_minutes"),double.PositiveInfinity))>=Num(Get(e,"minimum"),1);
        return Condition.Compile(Get(e,"condition"),"world").Evaluate(session.World.Read)==Truth.True;
    }
    object Assessment()
    {
        var checks=Items(Get(content,"expectations")).Select(e=>{
            var competition=Get(e,"drive_competition");
            var applicable=automaticViewer||competition.ValueKind!=JsonValueKind.Object||!Text(Get(competition,"action")).StartsWith(viewer+".",StringComparison.Ordinal);
            return new {id=Text(Get(e,"id")),applicable,passed=applicable?(bool?)Check(e):null,scope=applicable?"runtime":"not_applicable_player_choice"};}).ToArray();
        var missing=Items(Get(Get(content,"completion"),"facts")).Where(reference=>session.World.Read(Key(reference)) is not {Known:true,Conflicted:false} fact||fact.Value.ValueKind!=JsonValueKind.True).Select(Key).ToArray();
        var requiredKinds=new[]{("deduction","deduction"),("suggestion","suggestion"),("incantation","incantation")}
            .Where(kind=>Actors.Any(actor=>Items(Get(actor,"actions")).Any(action=>Get(action,kind.Item1).ValueKind==JsonValueKind.Object))).Select(kind=>kind.Item2).ToArray();
        var mechanics=requiredKinds.Select(kind=>new {kind,completed=session.MechanicHistory.Count(item=>item.Kind==kind&&item.Success),passed=session.MechanicHistory.Any(item=>item.Kind==kind&&item.Success)}).ToArray();
        return new {passed=(!HasCompletion||CampaignCompleted)&&checks.All(item=>!item.applicable||item.passed==true)&&mechanics.All(item=>item.passed)&&invariantFailures.Count==0&&failures==0,
            content_hash=definition.Hash,game_time=session.ContentTime,campaign_completed=CampaignCompleted,campaign_progress=Progress,
            assessment_scope="runtime_conditions_and_mechanics",emergence_assessment="requires_independent_causal_review",missing_completion=missing,failures,rejected_attempts=rejectedAttempts,blocked_attempts=blockedAttempts,
            total_action_receipts=version,successful_action_receipts=successfulActions,recoverable_cancellations=recoverableCancellations,
            invariant_failures=invariantFailures.ToArray(),checks,mechanics};
    }
    void CheckKnowledgeBoundaries()
    {
        foreach(var rule in Items(Get(content,"knowledge_boundaries")))
        {
            var actor=Text(Get(rule,"actor"));var key=Key(Get(rule,"ref"));
            if(session.View(actor).Knowledge.GetValueOrDefault(key) is {Known:true} && completed.GetValueOrDefault(Text(Get(rule,"after")))==0)
                invariantFailures.Add(actor+":"+key+" before "+Text(Get(rule,"after")));
        }
    }
    object Observe(int count=0,int successfulCount=0,int cancelledCount=0)
    {
        var options=Actions(viewer).Where(a=>session.Available(viewer,Text(Get(a,"id"))));
        if(selectedObject is not null)options=options.Where(a=>Text(Get(a,"target_object"))==selectedObject);
        var visibleMechanics=session.MechanicHistoryFor(viewer);
        object? LastVisible(string kind,object? fallback)
        {
            var receipt=visibleMechanics.LastOrDefault(item=>item.Actor==viewer&&item.Kind==kind);
            return receipt is null?VisibleMechanic(fallback):receipt.Details;
        }
        return new {active=Active,faulted=false,version,completed=successfulCount,receipts=count,recoverable_cancellations=cancelledCount,status=Status(),runtime=Status(),
            receipt_totals=new {total=version,successful=successfulActions,recoverable_cancellations=recoverableCancellations,rejected=rejectedAttempts,blocked=blockedAttempts,unexpected_failures=failures},
            content=new {hash=definition.Hash,schema="dv-script-v1"},receipt_path=receiptPath,
            audit_persistence=new {action_log=log?.Snapshot(),state_log=stateLog?.Snapshot()},
            readable_log_path=string.IsNullOrEmpty(receiptPath)?null:Path.ChangeExtension(receiptPath,"readable.txt"),readable_log_available_after_close=true,
            last_deduction=LastVisible("deduction",session.LastDeduction),last_opinion=LastVisible("suggestion",session.LastOpinion),last_incantation=LastVisible("incantation",session.LastIncantation),last_strategy=LastVisible("strategy",session.LastStrategy),
            mechanics=visibleMechanics.Select(item=>new {time=item.Time,execution=item.Execution,actor=item.Actor,action=item.Action,kind=item.Kind,success=item.Success,details=item.Details}).ToArray(),
            screen=new {viewer,room=Room(viewer),actors=Actors.Where(a=>Room(Text(Get(a,"id")))==Room(viewer)&&Get(a,"hidden").ValueKind!=JsonValueKind.True).Select(a=>new{id=Text(Get(a,"id")),name=Text(Get(a,"name"))}),
                objects=Items(Get(content,"fixtures")).Where(Visible).Select(f=>new{id=Text(Get(f,"id")),label=Text(Get(f,"label"))}),
                knowledge=session.View(viewer).Knowledge.Where(k=>k.Value.Known).Select(k=>new{key=k.Key,value=k.Value.Value,conflicted=k.Value.Conflicted,confidence=k.Value.Confidence}),needs=session.Needs(viewer),affect=session.Affect(viewer),player_paths=session.PlayerPaths(viewer),active_intent=session.ActiveIntent(viewer)},
            menu=selectedObject is null?null:new {level=1,shape="radial",target=selectedObject},
            options=options.Select(a=>new{id=Text(Get(a,"id")),label=Text(Get(a,"label")),kind=Text(Get(a,"kind")),target=Text(Get(a,"target_object")),
                deduction=Get(a,"deduction").ValueKind==JsonValueKind.Object?session.DeductionPreview(viewer,Text(Get(a,"id"))):null}).ToArray(),history=history.ToArray(),
            acceptance=Active?null:Assessment()};
    }
    void Receipt(ActionReceipt r)
    {
        version++;
        if(r.Committed){successfulActions++;completed[r.Action]=completed.GetValueOrDefault(r.Action)+1;firstCompletion.TryAdd(r.Action,r.Time);}
        else if(r.Interruption is not null)recoverableCancellations++;
        else if(r.Reason is "deduction_unproved" or "suggestion_rejected" or "incantation_precondition_failed")rejectedAttempts++;
        else if(r.Reason is "objective_condition_failed" or "standing_resource_busy")blockedAttempts++;
        else failures++;
        started.Remove(r.Execution,out var execution);
        decisionDrives.Remove(r.Execution,out var drive);
        decisionReasons.Remove(r.Execution,out var reasons);
        decisionAudits.Remove(r.Execution,out var decisionAudit);
        actionOutcomes.Remove(r.Execution,out var outcome);
        // A failed resource reservation is still a real chosen attempt. It has
        // no host dispatch, so recover its original private selection snapshot.
        if(execution is null&&outcome?.StartAttempt is { } attempt)
        {
            var action=session.Candidate(r.Actor,r.Action);
            execution=new(r.Actor,action,outcome.StartedAt,outcome.StartedAt+action.Duration,r.Execution,attempt.Options,r.Intent);
            drive=attempt.Drive;decisionAudit=attempt.Audit;
        }
        var start=execution?.StartedAt??r.Time;
        var focus=execution is null?"":Text(Get(execution.Action.Declaration,"focus"));
        var interaction=execution is null?"":Text(Get(execution.Action.Declaration,"interaction_slot"));
        if(r.Committed)
        {
            if(interaction.Length>0)
            {
                var capacity=(int)Num(Get(Items(Get(content,"slots")).FirstOrDefault(slot=>Text(Get(slot,"id"))=="interaction."+interaction),"capacity"),1);
                var overlapping=executions.Where(x=>x.Slot==interaction&&Math.Max(start,x.Start)<Math.Min(r.Time,x.End)-0.000001).ToArray();
                if(overlapping.Select(x=>Math.Max(start,x.Start)).Append(start).Any(time=>1+overlapping.Count(x=>x.Start<=time&&x.End>time)>capacity))
                    invariantFailures.Add("interaction capacity exceeded: "+interaction);
            }
            executions.Add((r.Action,interaction,start,r.Time));
        }
        var row=new Dictionary<string,object?> { ["receipt_index"]=version,["focus"]=focus,["interaction_slot"]=interaction,
            ["version"]=version,["chapter"]=(int)(start/60/1440)+1,["day"]=(int)(start/60/1440)+1,["start_time"]=start/60,["duration"]=(r.Time-start)/60,["actor"]=r.Actor,["action"]=r.Action,
            ["label"]=execution is null?"":Text(Get(execution.Action.Declaration,"label")),
            ["outcome"]=r.Committed?"completed":r.Reason,["execution_event"]=r.Execution,
            ["outcome_category"]=r.Committed?"completed":r.Interruption is not null?"recoverable_cancellation":r.Reason is "deduction_unproved" or "suggestion_rejected" or "incantation_precondition_failed"?"rejected":r.Reason is "objective_condition_failed" or "standing_resource_busy"?"blocked_attempt":"unexpected_failure",["interruption"]=r.Interruption,
            ["decision_drive"]=drive,["candidate_scores"]=execution?.Options,["decision_intent"]=r.Intent,
            ["decision_basis"]=reasons,["reason"]=execution is null?"":Text(Get(execution.Action.Declaration,"reason")),
            ["decision_audit"]=decisionAudit,
            ["actual_effects"]=outcome,
            ["mechanics"]=session.MechanicHistory.Where(item=>item.Execution==r.Execution).ToArray(),
            ["narrative"]=r.Narrative??[],
            ["needs"]=session.Needs(r.Actor),["room"]=Room(r.Actor),["knowledge_revision_before_refresh"]=session.View(r.Actor).KnowledgeRevision};
        AppendRecord(log,row,version);
        foreach(var line in r.Narrative??[])
            if(line.Recipients.Contains(viewer,StringComparer.Ordinal))
            {
                history.Add(new{actor=line.Speaker,action=r.Actor==viewer?r.Action:"",label=line.Text,speaker_label=line.SpeakerLabel,
                    evidence_id=line.EvidenceId,kind=line.Kind,completed=true,start_time=r.Time/60,duration=0});
                if(history.Count>16)history.RemoveAt(0);
            }
        if(Room(r.Actor)==Room(viewer)&&Get(Actors.Single(a=>Text(Get(a,"id"))==r.Actor),"hidden").ValueKind!=JsonValueKind.True)
        {
            var own=r.Actor==viewer;var declaration=execution?.Action.Declaration??default;
            var kind=Text(Get(declaration,"kind"));
            if(!own&&(kind is "deduce" or "strategy"||Get(declaration,"deduction").ValueKind==JsonValueKind.Object||Get(declaration,"strategy").ValueKind==JsonValueKind.Object))return;
            var label=own?Text(Get(declaration,"label")):kind switch {"walk"=>"移动到这里", "talk"=>"与同伴交谈", "inspect" or "read"=>"查看附近物件", _=>"与附近物件互动"};
            history.Add(new{actor=r.Actor,action=own?r.Action:"",label,completed=r.Committed,start_time=start/60,duration=(r.Time-start)/60,intent=own?r.Intent:null,interruption_label=own?r.Interruption?.Label:null});
            if(history.Count>16)history.RemoveAt(0);
        }
    }
    object Advance(int steps)
    {
        var before=version;var beforeSuccessful=successfulActions;var beforeCancelled=recoverableCancellations;
        // Batching speeds up wall time, never skips simulation boundaries or action costs.
        for(var n=0;n<Math.Clamp(steps,1,100)*300&&Active;n++)
        {
            session.Step(Math.Min(1,(end-session.ContentTime)*60),false,false);
            while(session.TryAction(out var decision))
            {
                started[decision!.Execution]=decision;
                decisionAudits[decision.Execution]=session.DecisionAudit(decision);
                if(decision.Options is { } options)firstOptions.TryAdd(decision.Action.Id,options);
                var drive=session.EvaluateDrive(decision.Actor,decision.Action.Id);
                decisionDrives[decision.Execution]=drive;firstDrives.TryAdd(decision.Action.Id,drive);
                var because=Get(decision.Action.Declaration,"because");
                if(because.ValueKind==JsonValueKind.Object&&Get(because,"op").ValueKind==JsonValueKind.Undefined)
                {
                    decisionReasons[decision.Execution]=because.EnumerateObject().Select(p=>{
                        var split=p.Name.LastIndexOf('.');var prefix=p.Name[..split];var layer=prefix.LastIndexOf('.');
                        var explicitFacet=layer>0&&prefix[(layer+1)..] is "phys" or "trace" or "lock" or "doc" or "infer";
                        var key=new FieldKey(explicitFacet?prefix[..layer]:prefix,explicitFacet?prefix[(layer+1)..]:"state",p.Name[(split+1)..]);
                        var fact=session.View(decision.Actor).Knowledge.GetValueOrDefault(key);
                        if(fact is not {Known:true,Conflicted:false}||(fact.Value.ValueKind==JsonValueKind.Number&&p.Value.ValueKind==JsonValueKind.Number?fact.Value.GetDouble()!=p.Value.GetDouble():fact.Value.GetRawText()!=p.Value.GetRawText()))invariantFailures.Add(decision.Action.Id+": missing intent evidence "+p.Name);
                        return new {key,value=fact?.Value,sources=session.Evidence(decision.Actor).Where(e=>e.Key==key).Select(e=>new{e.Id,e.Method,e.Source}).ToArray()};
                    }).ToArray();
                }
                else if(because.ValueKind==JsonValueKind.Object&&Condition.Compile(because,decision.Actor).Evaluate(k=>session.View(decision.Actor).Knowledge.GetValueOrDefault(k))!=Truth.True)
                    invariantFailures.Add(decision.Action.Id+": missing intent condition evidence");
                var wake=Num(Get(Actors.Single(a=>Text(Get(a,"id"))==decision.Actor),"wake_at_game_minutes"));
                if(decision.StartedAt/60<wake)invariantFailures.Add(decision.Actor+": acted before wake time");
                if(Get(decision!.Action.Declaration,"requires_host_completion").ValueKind==JsonValueKind.True)
                    throw new InvalidDataException("CLI requires a declared logical execution; cannot forge a physical host completion.");
            }
            while(session.TryActionOutcome(out var outcome))actionOutcomes[outcome!.Execution]=outcome;
            while(session.TryReceipt(out var receipt))Receipt(receipt!);
            RecordAffects();
            CheckKnowledgeBoundaries();
        }
        // Commit actions due exactly at the authored horizon without advancing the clock.
        if(!Active){session.Step(0,false,false);while(session.TryActionOutcome(out var outcome))actionOutcomes[outcome!.Execution]=outcome;while(session.TryReceipt(out var receipt))Receipt(receipt!);RecordAffects();WriteEvidenceCoverage();if(!string.IsNullOrEmpty(receiptPath))File.WriteAllText(Path.ChangeExtension(receiptPath,"acceptance.json"),Encode(Assessment()));}
        return Observe((int)(version-before),successfulActions-beforeSuccessful,recoverableCancellations-beforeCancelled);
    }
    void RecordAffects()
    {
        foreach(var actorDefinition in Actors)
        {
            var actor=Text(Get(actorDefinition,"id"));var evidence=session.Evidence(actor);
            var cursor=evidenceCursors.GetValueOrDefault(actor);
            if(cursor>evidence.Count)throw new InvalidDataException("Committed evidence history shrank while writing audit: "+actor);
            for(var index=cursor;index<evidence.Count;index++)
            {
                var item=evidence[index];
                var isCommunication=new[]{"handoff/","mechanic/","report/","dialogue/","utterance/"}.Any(prefix=>item.Id.StartsWith(prefix,StringComparison.Ordinal));
                var isPerception=item.Id.StartsWith("perception/",StringComparison.Ordinal);
                var isInference=item.Method=="inference";
                var isProof=item.Id.StartsWith("proof/",StringComparison.Ordinal);
                var isMagic=item.Id.StartsWith("incantation/",StringComparison.Ordinal);
                var isOpinion=item.Id.StartsWith("opinion/",StringComparison.Ordinal);
                var internalState=item.Key.Object.StartsWith("event:",StringComparison.Ordinal)||item.Key.Field is "room" or "spot";
                var isObservation=item.Id.StartsWith("action/",StringComparison.Ordinal);
                var sourceAction=Text(Get(item.Source,"action"));var label="";
                if(isProof)label="[脑内推演完成] "+Text(Get(item.Source,"query"));
                else if(isMagic)label="[言灵回执] "+Text(Get(item.Source,"formula"));
                else if(isOpinion)label=Get(item.Source,"accepted").ValueKind==JsonValueKind.True?"[建议被采纳]":"[建议被拒绝]";
                else if(isInference)
                {
                    var basis=Get(item.Source,"basis");
                    label="[推理更新] "+(basis.ValueKind==JsonValueKind.Object?string.Join("；",new[]{("facts","观测事实"),("excluded","排除与保留"),("conclusion","当前结论"),("question","下一问")}.Select(part=>part.Item2+"："+Text(Get(basis,part.Item1)))):Text(basis));
                }
                else
                {
                    var speaker=isCommunication?Text(Get(item.Source,"actor")):actor;
                    var name=Text(Get(item.Source,"speaker_label"),Text(Get(Actors.FirstOrDefault(a=>Text(Get(a,"id"))==speaker),"name"),speaker.Length>0?speaker:"环境"));
                    var fieldLabel=Text(Get(Get(content,"fact_labels"),item.Key.Object+"."+item.Key.Facet+"."+item.Key.Field));
                    var message=fieldLabel.Length>0&&item.Key.Field=="exit"?fieldLabel:item.Value.ValueKind==JsonValueKind.String?item.Value.GetString()!.TrimEnd('。','，'):
                        fieldLabel.Length>0?fieldLabel+(item.Value.ValueKind==JsonValueKind.True?"":item.Value.ValueKind==JsonValueKind.False?"：否":"："+item.Value.GetRawText()):
                        item.Key.Facet=="state"?"状态更新":item.Value.GetRawText();
                    label=isCommunication?"[获知] 来自"+name+"："+message:isPerception?"["+(Text(Get(item.Source,"channel"))=="hearing"?"听觉感知":Text(Get(item.Source,"channel"))=="blocked"?"交互受阻与感知":"视线感知")+"] "+Text(Get(item.Source,"label"))+"；"+message:"[观察所得] "+message;
                }
                var row=new Dictionary<string,object?>{["receipt_index"]=++stateIndex,["kind"]=internalState?"internal_state":isProof?"deduction":isMagic?"incantation":isOpinion?"opinion":isInference?"inference":isCommunication?"communication_received":isPerception?"perception":isObservation?"observation":"evidence",["start_time"]=item.Time,["recorded_time"]=session.ContentTime,["duration"]=0,
                    ["actor"]=actor,["action"]=sourceAction,["label"]=label,
                    ["outcome"]="completed",["room"]=Room(actor),["actor_evidence_sequence"]=index+1,["evidence_id"]=item.Id,["source"]=item.Source,["fact_ref"]=item.Key,["fact_value"]=item.Value,["confidence"]=item.Confidence,["method"]=item.Method};
                AppendRecord(stateLog,row,stateIndex);
                evidenceWritten[actor]=evidenceWritten.GetValueOrDefault(actor)+1;
            }
            evidenceCursors[actor]=evidence.Count;
        }
        foreach(var (actor,item) in session.DrainAffectEvents())
        {
            affectEvents.Add((actor,item));
            var row=new Dictionary<string,object?>{["receipt_index"]=++stateIndex,["kind"]=item.Kind,["start_time"]=item.Time/60,["duration"]=item.Duration/60,
                ["actor"]=actor,["action"]=item.Source,["label"]=item.Label,["outcome"]="completed",["room"]=Room(actor)};
            AppendRecord(stateLog,row,stateIndex);
        }
    }
    void WriteEvidenceCoverage()
    {
        if(string.IsNullOrEmpty(receiptPath))return;
        var actionCoverage=log!.VerifiedCoverage();var stateCoverage=stateLog!.VerifiedCoverage();
        var actors=Actors.Select(declaration=>Text(Get(declaration,"id"))).Select(actor=>new {
            actor,committed=session.EvidenceCount(actor),recorded=evidenceWritten.GetValueOrDefault(actor),cursor=evidenceCursors.GetValueOrDefault(actor),
            pending=session.PendingInformation(actor),last_source_game_minute=session.Evidence(actor).LastOrDefault()?.Time}).ToArray();
        File.WriteAllText(Path.ChangeExtension(receiptPath,"evidence-coverage.json"),Encode(new {schema="committed-evidence-coverage-v1",content_hash=definition.Hash,game_time=session.ContentTime,
            action_log=actionCoverage,state_log=stateCoverage,
            complete=actors.All(actor=>actor.committed==actor.recorded&&actor.committed==actor.cursor),actors}));
    }
    object Select(JsonElement request)
    {
        if(!Active)throw new InvalidOperationException("The DV time horizon has been reached.");
        var choice=Text(Get(request,"choice_id"));
        var id=choice.StartsWith("object:",StringComparison.Ordinal)?choice[7..]:Text(Get(request,"object_id"));
        if(id.Length>0)
        {
            if(!Items(Get(content,"fixtures")).Any(f=>Text(Get(f,"id"))==id&&Visible(f)))throw new InvalidOperationException("Object is outside the viewer's visible room.");
            selectedObject=id;return Observe(); // Opening the first-level menu consumes no time and never starts movement.
        }
        var action=Text(Get(request,"choice_id"),Text(Get(request,"action_id")));
        if(!session.Available(viewer,action))throw new InvalidOperationException("Action is not available to this actor.");
        if(Get(request,"evidence_ids").ValueKind==JsonValueKind.Array)
            session.SubmitDeduction(viewer,action,Items(Get(request,"evidence_ids")).Select(item=>Text(item)).ToArray());
        else session.Submit(viewer,action);
        selectedObject=null;return Observe();
    }
    public void Dispose()
    {
        if(disposed)return;
        disposed=true;
        try{RecordAffects();WriteEvidenceCoverage();}
        finally{stateLog?.Dispose();log?.Dispose();}
        if(!string.IsNullOrEmpty(receiptPath)&&File.Exists(receiptPath))
            ReadableEventLog.Write(receiptPath,content,Path.ChangeExtension(receiptPath,"readable.txt"));
    }
    public static int ValidateContent()
    {
        try
        {
            using var doc=JsonDocument.Parse("{\"controller\":\"ai\"}");using var host=new NativeCli(doc.RootElement);
            Console.WriteLine("PASS independent Core DV new-game initialization");
            var before=host.session.SaveState();
            _=host.Observe();_=host.Observe();
            CharacterContentRevisions.AssertStatePreserved(before,host.session.SaveState());
            Console.WriteLine("PASS player-path advice is a read-only projection of the real new game");
            if(GoalPlanningChecks.Run()!=0)throw new InvalidDataException("Personal goal planning checks failed.");
            ValidateContentRevisions();return 0;
        }
        catch(Exception e){Console.Error.WriteLine(e);return 1;}
    }
    static void ValidateContentRevisions()
    {
        var directory="assets/data/content-revisions";
        if(!Directory.Exists(directory))return;
        var next=CharacterContentRevisions.Capture("res://"+DefaultContent,path=>File.ReadAllText(PathOf(path)));
        RuntimeSession Make(CharacterContentSnapshot snapshot)
        {
            var declaration=snapshot.Definition.Declaration;
            var primary=Get(declaration,"deduction");
            var created=snapshot.Definition.Create(primary.ValueKind==JsonValueKind.Object?snapshot.Revision.Sources[Text(Get(primary,"source"))]:null);
            foreach(var item in Items(Get(declaration,"deductions")))created.ConfigureDeduction(snapshot.Revision.Sources[Text(Get(item,"source"))],item);
            foreach(var item in Items(Get(declaration,"strategy_activities")))created.ConfigureStrategy(snapshot.Revision.Sources[Text(Get(item,"source"))],item);
            return created;
        }
        foreach(var path in Directory.EnumerateFiles(directory,"*.json.gz").OrderBy(p=>p,StringComparer.Ordinal))
        {
            var previous=CharacterContentRevisions.ReadCompressed(File.ReadAllBytes(path));
            if(previous.Revision.EntryPath!=next.Revision.EntryPath)continue;
            if(Path.GetFileName(path)!=previous.Revision.Fingerprint+".json.gz")throw new InvalidDataException("Published revision filename does not identify its verified sources.");
            var previousState=Make(previous).SaveState();
            CharacterContentUpdate? update=null;string? incompatibility=null;
            try{update=CharacterContentRevisions.Validate(previous,next,previousState);}
            catch(InvalidDataException error){incompatibility=error.Message;}
            if(update is not null)
            {
                var restored=Make(next);restored.RestoreState(previousState);
                var stateHash=CharacterContentRevisions.AssertStatePreserved(previousState,restored.SaveState());
                Console.WriteLine($"PASS compatible content revision {previous.Revision.Fingerprint}: added_manual_routes={update.AddedManualRoutes.Length}, tightened_actions={update.TightenedActions.Length}, state_preserved={stateHash}");
            }
            else Console.WriteLine($"REQUIRES_NEW_GAME authenticated revision {previous.Revision.Fingerprint}: {incompatibility}");
            // A published old revision remains authentic even when a later release
            // intentionally changes initial facts. Exercise rejection cases against
            // the current declaration itself, not an already incompatible baseline.
            var saved=Make(next).SaveState();
            var rejected=0;
            void Reject(string label,Action operation)
            {
                try{operation();}
                catch(InvalidDataException){rejected++;return;}
                throw new InvalidDataException("Content compatibility accepted an unsafe authoring change: "+label);
            }
            void RejectDeclaration(string label,Action<JsonObject> change)
            {
                var changed=JsonNode.Parse(next.Definition.Declaration.GetRawText())!.AsObject();change(changed);
                Reject(label,()=>CharacterContentRevisions.ValidateDeclarations(next.Definition.Declaration,JsonSerializer.SerializeToElement(changed),saved));
            }
            RejectDeclaration("initial world time",root=>root["physical"]!["time"]=root["physical"]!["time"]!.GetValue<double>()+1);
            RejectDeclaration("actor removal",root=>root["actors"]!.AsArray().RemoveAt(root["actors"]!.AsArray().Count-1));
            RejectDeclaration("existing action duration",root=>
            {
                var action=root["actors"]![0]!["actions"]![0]!;
                action["duration_seconds"]=action["duration_seconds"]!.GetValue<double>()+1;
            });
            RejectDeclaration("existing physical effects",root=>root["physical"]!["adoptions"]!.AsObject().First().Value!["law"]!["effects"]!.AsArray().Clear());
            RejectDeclaration("weakened admission",root=>root["actors"]![0]!["actions"]![0]!["precondition"]=JsonSerializer.SerializeToNode(new{op="constant",value=true}));
            RejectDeclaration("acceptance removal",root=>root["expectations"]!.AsArray().RemoveAt(0));
            RejectDeclaration("actor autonomy changed",root=>
            {
                var actor=root["actors"]![0]!;
                actor["autonomous"]=!actor["autonomous"]!.GetValue<bool>();
            });
            var wrong=(previous.Revision.Fingerprint[0]=='0'?"1":"0")+previous.Revision.Fingerprint[1..];
            Reject("forged source fingerprint",()=>CharacterContentRevisions.Verify(previous.Revision with{Fingerprint=wrong}));
            Console.WriteLine($"PASS authenticated content revision {previous.Revision.Fingerprint}: rejected_unsafe_changes={rejected}; compatibility={(update is null?"requires-new-game":"preserves-state")}");
        }
    }
    public static void Run()
    {
        NativeCli? host=null;
        try {while(Console.ReadLine() is { } line)
        {
            long requestId=0;
            try
            {
                using var doc=JsonDocument.Parse(line);var request=doc.RootElement;requestId=(long)Num(Get(request,"id"));var type=Text(Get(request,"type"));object result;
                if(type=="open"){host?.Dispose();host=new(Get(request,"options"));result=host.Observe();}
                else if(type=="close")
                {
                    var readable=string.IsNullOrEmpty(host?.receiptPath)?null:Path.ChangeExtension(host.receiptPath,"readable.txt");
                    host?.Dispose();host=null;
                    Console.WriteLine(Encode(new{id=requestId,result=new{closed=true,readable_log_path=readable,readable_log_written=readable is not null&&File.Exists(readable)}}));break;
                }
                else if(host is null)throw new InvalidOperationException("Open a session first.");
                else result=type switch {"advance"=>host.Advance((int)Num(Get(request,"steps"),1)),"select"=>host.Select(request),"observe"=>host.Observe(),_=>throw new InvalidOperationException("Unsupported operation.")};
                Console.WriteLine(Encode(new{id=requestId,result}));
            }
            catch(Exception e){Console.WriteLine(Encode(new{id=requestId,error=e.ToString()}));}
        }}finally{host?.Dispose();}
    }
}
