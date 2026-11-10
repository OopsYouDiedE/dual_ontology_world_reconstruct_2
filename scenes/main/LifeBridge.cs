using Godot;
using System.Text.Json;
using System.Text.Json.Nodes;
using DuelView.Runtime;

namespace DualOntologyWorldReconstruct2;

public partial class LifeBridge : Node
{
    private CharacterSessionDefinition? definition;
    private RuntimeSession? session;
    private readonly Dictionary<long,Decision> decisions=[];
    private readonly List<ActionReceipt> receipts=[];
    private string contentPath="res://assets/data/scenarios/life_simulation.dv";
    private string error="";
    private string auditDirectory="";
    private readonly Dictionary<string,string> disabledReasons=[];
    private static string Encode(object? value)=>JsonSerializer.Serialize(value);
    private static string Read(string path)=>System.IO.File.ReadAllText(ProjectSettings.GlobalizePath(path));
    public string Open(string path,string buildingJson,int seed)
    {
        try
        {
            contentPath=path.Length==0?contentPath:path;
            var source=Read(contentPath);
            if(buildingJson.Length>0)
            {
                var candidate="res://tools/building_construction/candidates/life-"+Guid.NewGuid().ToString("N")+".dv";
                System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(ProjectSettings.GlobalizePath(candidate))!);
                System.IO.File.WriteAllText(ProjectSettings.GlobalizePath(candidate),"schema \"dv-script-v1\";\ndata life.building { value = "+JsonNode.Parse(buildingJson)!.ToJsonString()+"; }\n");
                var document=DuelView.Dv.DvDocument.Parse(source).Definition("data","runtime.character_session").GetProperty("value");
                var root=JsonNode.Parse(document.GetRawText())!.AsObject();root["building_source"]=candidate;
                source="schema \"dv-script-v1\";\ndata runtime.character_session { value = "+root.ToJsonString()+"; }\n";
            }
            definition=new(source,Read("res://assets/data/98-runtime-session.data.dv"),Read);
            session=definition.Create();session.ConfigureLifeSeed(seed);session.ConfigureVisibleRoom("house");
            decisions.Clear();receipts.Clear();disabledReasons.Clear();error="";
            auditDirectory=ProjectSettings.GlobalizePath("res://.runtime/life-sessions/"+Guid.NewGuid().ToString("N"));
            System.IO.Directory.CreateDirectory(auditDirectory);
            System.IO.File.WriteAllText(System.IO.Path.Combine(auditDirectory,"content.dv"),source);
            System.IO.File.WriteAllText(System.IO.Path.Combine(auditDirectory,"manifest.json"),Encode(new {definition.Hash,contentPath,seed,host="godot",started=DateTimeOffset.UtcNow}));
            return Encode(new {ok=true,definition=session.LifeDefinition,audit_directory=auditDirectory});
        }
        catch(Exception exception){error=exception.ToString();GD.PushError(error);return Encode(new {ok=false,error});}
    }
    public string Step(double seconds)
    {
        if(session is null||definition is null)return Encode(new {error="尚未开局"});
        try
        {
            var before=session.ContentTime;
            if(!CampaignProgress.Evaluate(definition.Declaration,session).Completed)session.StepPhysical(seconds);
            var dispatch=new List<object>();
            while(session.TryAction(out var decision))
            {
                decisions[decision!.Execution]=decision;
                dispatch.Add(new {execution=decision.Execution,actor=decision.Actor,meta=decision.Action.Declaration.GetProperty("life"),duration=decision.Action.Duration,
                    label=Label(decision.Action.Declaration),options=decision.Options});
            }
            while(session.TryCancellation(out var cancelled))session.ConfirmCancelled(cancelled!);
            while(session.TryActionOutcome(out var outcome))
                System.IO.File.AppendAllText(System.IO.Path.Combine(auditDirectory,"outcomes.jsonl"),Encode(new {outcome,mechanics=session.MechanicHistory.Where(item=>item.Execution==outcome!.Execution)})+"\n");
            while(session.TryReceipt(out var receipt))
            {
                receipts.Add(receipt!);decisions.Remove(receipt!.Execution);
                System.IO.File.AppendAllText(System.IO.Path.Combine(auditDirectory,"actions.jsonl"),Encode(receipt)+"\n");
            }
            return Encode(new {dispatch,elapsed_seconds=(session.ContentTime-before)*60,snapshot=SnapshotValue()});
        }
        catch(Exception exception){error=exception.ToString();GD.PushError(error);return Encode(new {error});}
    }
    private static string Label(JsonElement action)=>action.TryGetProperty("label",out var label)?label.GetString()??"":"";
    public bool SetTarget(long execution,double positionX,double positionY,double positionZ,double distance,double speed)=>session is not null&&decisions.TryGetValue(execution,out var decision)&&session.SetNavigationTarget(decision,"house",positionX,positionY,positionZ,distance,speed);
    public bool Progress(long execution,double positionX,double positionY,double positionZ,double distance)=>session is not null&&decisions.TryGetValue(execution,out var decision)&&session.ReportNavigationProgress(decision,positionX,positionY,positionZ,distance);
    public bool Arrive(long execution,double positionX,double positionY,double positionZ)=>session is not null&&decisions.TryGetValue(execution,out var decision)&&session.Arrive(decision,positionX,positionY,positionZ);
    public void Fail(long execution,string reason)
    {
        if(session is null||!decisions.TryGetValue(execution,out var decision))return;
        session.HostFailed(decision,reason);disabledReasons[decision.Action.Id]=reason;
    }
    public void Place(string actor,double positionX,double positionY,double positionZ,double yaw)=>session?.ReportPlacement(actor,positionX,positionY,positionZ,yaw,"house");
    public string Observe()=>Encode(SnapshotValue());
    public string InspectCognition(string actor)=>Encode(session?.CognitionAudit(actor,true));
    public string Navigation()=>Encode(decisions.Values.Where(decision=>session?.Activity(decision.Actor)?.Phase=="approaching")
        .Select(decision=>new {execution=decision.Execution,actor=decision.Actor,meta=decision.Action.Declaration.GetProperty("life"),label=Label(decision.Action.Declaration)}));
    private object SnapshotValue()
    {
        if(session is null||definition is null)return new {started=false,error};
        var life=session.LifeDefinition;var progress=CampaignProgress.Evaluate(definition.Declaration,session);
        return new {started=true,active=!progress.Completed,campaign_completed=progress.Completed,time=session.ContentTime,error,progress,
            actors=life.GetProperty("agents").EnumerateArray().Select(profile=>
            {
                var id=profile.GetProperty("id").GetString()!;var activity=session.Activity(id);
                return new {id,name=profile.GetProperty("name").GetString(),needs=session.Needs(id),placement=session.Placement(id),activity,
                    food=session.World.Read(new(id,"state","food"))?.Value,book=session.World.Read(new(id,"state","book"))?.Value,
                    purpose=session.View(id).Knowledge.GetValueOrDefault(new(id,"doc","personal_purpose"))?.Value,
                    evidence_count=session.EvidenceCount(id),cognition=session.CognitionAudit(id),choices=definition.Declaration.GetProperty("actors").EnumerateArray().First(actor=>actor.GetProperty("id").GetString()==id).GetProperty("actions").EnumerateArray()
                        .Where(action=>session.Available(id,action.GetProperty("id").GetString()!)).Select(action=>new {id=action.GetProperty("id").GetString(),label=Label(action)}).ToArray()};
            }).ToArray(),
            objects=life.GetProperty("objects").EnumerateArray().Select(item=>new {id=item.GetProperty("id").GetString(),lamp=session.World.Read(new(item.GetProperty("id").GetString()!,"state","lamp"))?.Value}).ToArray(),
            audit=session.LifeAudit(),audit_status=new {receipt_count=receipts.Count,successful_count=receipts.Count(item=>item is ActionReceipt {Committed:true}),
                recoverable_cancellations=receipts.Count(item=>item is ActionReceipt {Reason:"cancelled"}),rejected_count=0,
                blocked_attempt_count=receipts.Count(item=>item is ActionReceipt {Reason:"standing_resource_busy" or "life_condition_changed" or "objective_condition_failed"}),
                unexpected_failure_count=receipts.Count(item=>item is ActionReceipt {Committed:false} receipt&&receipt.Reason is not ("cancelled" or "standing_resource_busy" or "life_condition_changed" or "objective_condition_failed" or "navigation_unreachable"))},
            mechanics=session.MechanicHistory.TakeLast(40).ToArray(),receipts=receipts.TakeLast(30).ToArray(),disabled=disabledReasons,audit_directory=auditDirectory};
    }
    public string Submit(string actor,string action)
    {
        if(session is null)return "尚未开局";
        try{session.SetAutonomy(actor,false);session.Submit(actor,action);session.SetAutonomy(actor,true);return "";}
        catch(Exception exception){session.SetAutonomy(actor,true);return exception.Message;}
    }
    public string Save(string path)
    {
        if(session is null||definition is null)return "尚未开局";
        System.IO.File.WriteAllText(ProjectSettings.GlobalizePath(path),Encode(new {hash=definition.Hash,state=session.SaveState(),receipts}));return "";
    }
    public string Load(string path)
    {
        if(session is null||definition is null)return "尚未开局";
        try
        {
            using var document=JsonDocument.Parse(Read(path));var root=document.RootElement;
            if(root.GetProperty("hash").GetString()!=definition.Hash)return "存档内容版本不同，需要兼容迁移或新局。";
            var replacement=definition.Create();replacement.RestoreState(root.GetProperty("state").Deserialize<RuntimeSessionState>()!);
            session=replacement;decisions.Clear();
            receipts.Clear();disabledReasons.Clear();
            if(root.TryGetProperty("receipts",out var savedReceipts))receipts.AddRange(savedReceipts.Deserialize<ActionReceipt[]>()!);
            System.IO.File.AppendAllText(System.IO.Path.Combine(auditDirectory,"session-events.jsonl"),Encode(new {kind="load",path,time=session.ContentTime,hash=definition.Hash})+"\n");
            foreach(var execution in session.SaveState().Executions)
                if(session.DecisionFor(execution.Execution) is { } decision)decisions.Add(execution.Execution,decision);
            return "";
        }
        catch(Exception exception){return exception.Message;}
    }
    public string Reload(string path)
    {
        if(session is null||definition is null)return "尚未开局";
        try
        {
            var replacement=new CharacterSessionDefinition(Read(path),Read("res://assets/data/98-runtime-session.data.dv"),Read);
            var saved=session.SaveState();
            CharacterContentRevisions.ValidateDeclarations(definition.Declaration,replacement.Declaration,saved);
            var restored=replacement.Create();restored.RestoreState(saved);
            CharacterContentRevisions.AssertStatePreserved(saved,restored.SaveState());
            definition=replacement;session=restored;contentPath=path;
            decisions.Clear();
            foreach(var execution in saved.Executions)
                if(session.DecisionFor(execution.Execution) is { } decision)decisions.Add(execution.Execution,decision);
            return "";
        }
        catch(Exception exception){return "内容未重载，原会话保留："+exception.Message;}
    }
    public void Close()
    {
        if(session is null)return;
        System.IO.File.WriteAllText(System.IO.Path.Combine(auditDirectory,"final.json"),Observe());session=null;decisions.Clear();
    }
    public override void _ExitTree()=>Close();
}
