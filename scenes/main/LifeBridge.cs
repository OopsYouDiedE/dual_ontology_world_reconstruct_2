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
    private string sourceManifest="";
    private bool customBuilding, multilevel;
    private string error="";
    private string auditDirectory="";
    private readonly Dictionary<string,string> disabledReasons=[];
    private JsonObject notes=new();
    private Dictionary<string,string> doorStates=new(StringComparer.Ordinal);
    private Dictionary<string,Doorway> doorways=new(StringComparer.Ordinal);
    private sealed record Doorway(double X,double Y,double Z,double Ux,double Uz,double Width,double Height,double Thickness);
    private GodotObject? objectRouteSpace;
    private Godot.Collections.Dictionary? objectRouteActions;
    private bool physicalObjectRoute;
    private readonly Dictionary<(double X,double Y,double Z,string Object,string Action,int Slot),double?> objectRoutes=[];

    public void SetObjectRouteSpace(GodotObject space,Godot.Collections.Dictionary actions)
    {
        physicalObjectRoute=false;
        objectRouteSpace=space;
        objectRouteActions=actions;
        BindObjectRouteProbe();
    }
    public void SetObjectRouteSpace3D(GodotObject space,Godot.Collections.Dictionary actions)
    {
        physicalObjectRoute=true;
        objectRouteSpace=space;
        objectRouteActions=actions;
        BindObjectRouteProbe();
    }
    private void BindObjectRouteProbe()
    {
        objectRoutes.Clear();
        if(physicalObjectRoute&&objectRouteSpace is not null)
        {
            var states=new Godot.Collections.Dictionary();
            foreach(var item in doorStates)states[item.Key]=item.Value;
            objectRouteSpace.Call("set_door_states",states);
        }
        session?.ConfigureLifeObjectRoute(objectRouteSpace is not null?ProbeObjectRoute:null);
    }
    private double? ProbeObjectRoute(PhysicalPlacement from,string obj,string action,int slot)
    {
        var key=(from.X,from.Y,from.Z,obj,action,slot);
        if(objectRoutes.TryGetValue(key,out var cached))return cached;
        var result=physicalObjectRoute
            ?objectRouteSpace!.Call("physical_object_route_length",from.X,from.Y,from.Z,obj,action,slot,objectRouteActions!)
            :objectRouteSpace!.Call("object_route_length",from.X,from.Z,obj,action,slot,objectRouteActions!);
        var distance=result.VariantType==Variant.Type.Float?result.AsDouble():double.PositiveInfinity;
        return objectRoutes[key]=double.IsFinite(distance)&&distance>=0?distance:null;
    }
    private static string Encode(object? value)=>JsonSerializer.Serialize(value);
    private static string Read(string path)=>System.IO.File.ReadAllText(ProjectSettings.GlobalizePath(path));
    private static CharacterSessionDefinition Prepare(string source,string buildingJson,bool multilevel=false)
    {
        const string buildingPath="res://session-building.dv";
        if(buildingJson.Length>0)
        {
            var document=DuelView.Dv.DvDocument.Parse(source).Definition("data","runtime.character_session").GetProperty("value");
            var root=JsonNode.Parse(document.GetRawText())!.AsObject();root["building_source"]=buildingPath;
            if(multilevel)root["life_multilevel"]=true;
            source="schema \"dv-script-v1\";\ndata runtime.character_session { value = "+root.ToJsonString()+"; }\n";
        }
        string ReadContent(string path)=>path==buildingPath
            ?"schema \"dv-script-v1\";\ndata life.building { value = "+JsonNode.Parse(buildingJson)!.ToJsonString()+"; }\n":Read(path);
        var prepared=new CharacterSessionDefinition(source,Read("res://assets/data/98-runtime-session.data.dv"),ReadContent);
        if(!prepared.Create().IsLifeSession)throw new InvalidDataException("This entry requires a life scenario. Use the CLI host for case scenarios.");
        return prepared;
    }
    public string Open(string path,string buildingJson,int seed)
    {
        try
        {
            contentPath=path.Length==0?contentPath:path;
            var source=Read(contentPath);
            sourceManifest=source;
            customBuilding=buildingJson.Length>0;
            multilevel=customBuilding&&JsonNode.Parse(buildingJson)?["layers"] is JsonArray {Count:>1};
            definition=Prepare(source,buildingJson,multilevel);
            session=definition.Create();session.ConfigureLifeSeed(seed);session.ConfigureVisibleRoom("house");
            doorways=ReadDoorways(session.LifeDefinition.GetProperty("building"));doorStates.Clear();
            decisions.Clear();receipts.Clear();disabledReasons.Clear();notes=new();error="";
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
        if(session is null||definition is null)return Encode(new {error="The simulation has not started."});
        try
        {
            // The installed grid is immutable. Reuse routes for stationary actors,
            // including the eligibility list shown by SnapshotValue.
            if(objectRoutes.Count>=2048)objectRoutes.Clear();
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
    public string Definition()=>Encode(session?.LifeDefinition);
    public string InspectCognition(string actor)=>Encode(session?.CognitionAudit(actor,true));
    public string Journal(string actor)
    {
        if(session is null)return Encode(new {viewer=actor});
        var view=session.View(actor);
        var cognition=definition!.Declaration.GetProperty("actors").EnumerateArray().Single(profile=>profile.GetProperty("id").GetString()==actor);
        return Encode(new {viewer=actor,time=session.ContentTime,knowledge=view.Knowledge.Where(item=>item.Value.Known)
            .Select(item=>new {key=item.Key.ToString(),subject=item.Key.Object,facet=item.Key.Facet,field=item.Key.Field,fact=item.Value}).ToArray(),
            evidence=session.Evidence(actor),map=view.RememberedMap,cognition=session.CognitionAudit(actor,true),
            rules=cognition.TryGetProperty("cognition",out var mind)&&mind.TryGetProperty("theory",out var theory)?theory:default(JsonElement?),
            notes=notes[actor]?.DeepClone(),receipts=receipts.Where(item=>item.Actor==actor).TakeLast(60).ToArray()});
    }
    public string SaveNote(string actor,string title,string text,string related,string judgement,string identity)
    {
        if(session is null)return "The simulation has not started.";
        _=session.View(actor);
        var entries=notes[actor] as JsonArray;
        if(entries is null){entries=new();notes[actor]=entries;}
        if(identity.Length==0)identity=Guid.NewGuid().ToString("N");
        var index=entries.Select((item,index)=>(item,index)).FirstOrDefault(item=>item.item?["id"]?.GetValue<string>()==identity).index;
        var existing=entries.FirstOrDefault(item=>item?["id"]?.GetValue<string>()==identity);
        var note=JsonSerializer.SerializeToNode(new {id=identity,title,text,related,judgement,time=session.ContentTime});
        if(existing is null)entries.Add(note);else entries[index]=note;
        return "";
    }
    public string Navigation()=>Encode(decisions.Values.Where(decision=>session?.Activity(decision.Actor)?.Phase=="approaching")
        .Select(decision=>new {execution=decision.Execution,actor=decision.Actor,meta=decision.Action.Declaration.GetProperty("life"),label=Label(decision.Action.Declaration)}));
    private object SnapshotValue()
    {
        if(session is null||definition is null)return new {started=false,error};
        var life=session.LifeDefinition;var progress=CampaignProgress.Evaluate(definition.Declaration,session);
        return new {started=true,door_states=doorStates,active=!progress.Completed,campaign_completed=progress.Completed,time=session.ContentTime,error,progress,
            actors=life.GetProperty("agents").EnumerateArray().Select(profile=>
            {
                var id=profile.GetProperty("id").GetString()!;var activity=session.Activity(id);
                JsonElement? motor=activity is not null&&session.Candidate(id,activity.Action).Declaration.TryGetProperty("motor",out var presentation)?presentation:null;
                return new {id,name=profile.GetProperty("name").GetString(),needs=session.Needs(id),placement=session.Placement(id),activity,motor,
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
        if(session is null)return "The simulation has not started.";
        try{session.SetAutonomy(actor,false);session.Submit(actor,action);session.SetAutonomy(actor,true);return "";}
        catch(Exception exception){session.SetAutonomy(actor,true);return exception.Message;}
    }
    private static Dictionary<string,Doorway> ReadDoorways(JsonElement building)
    {
        var result=new Dictionary<string,Doorway>(StringComparer.Ordinal);
        var ambiguous=new HashSet<string>(StringComparer.Ordinal);
        foreach(var wall in building.GetProperty("walls").EnumerateArray())
        {
            if(!wall.TryGetProperty("openings",out var openings))continue;
            var points=wall.GetProperty("points").EnumerateArray().ToArray();
            foreach(var opening in openings.EnumerateArray())
            {
                if(opening.GetProperty("type").GetString() is not ("closed_door" or "arched_closed_door" or "double_door")||
                   !opening.TryGetProperty("id",out var identity)||identity.GetString() is not {Length:>0} id)continue;
                int segment=(int)opening.GetProperty("segment").GetDouble();
                if(segment<0||segment+1>=points.Length||ambiguous.Contains(id))continue;
                var a=points[segment];var b=points[segment+1];
                double x=a[0].GetDouble(),y=a[1].GetDouble(),z=a[2].GetDouble();
                double dx=b[0].GetDouble()-x,dz=b[2].GetDouble()-z;
                double length=Math.Sqrt(dx*dx+dz*dz);
                if(length<0.01)continue;
                dx/=length;dz/=length;
                double center=opening.GetProperty("center").GetDouble();
                if(!result.TryAdd(id,new(x+dx*center,y+opening.GetProperty("bottom").GetDouble(),z+dz*center,
                    dx,dz,opening.GetProperty("width").GetDouble(),opening.GetProperty("height").GetDouble(),wall.GetProperty("thickness").GetDouble())))
                {
                    result.Remove(id);ambiguous.Add(id);
                }
            }
        }
        return result;
    }
    public string DoorControls()=>Encode(doorways.Keys.Select(id=>new {id,state=doorStates.GetValueOrDefault(id,"open")}));
    public string ChangeDoor(string id,string operation)
    {
        if(session is null||!doorways.TryGetValue(id,out var doorway))return "That door is unavailable.";
        string before=doorStates.GetValueOrDefault(id,"open");
        string? after=(before,operation) switch
        {
            ("open","toggle")=>"closed", ("closed","toggle")=>"open",
            ("open" or "closed","lock")=>"locked", ("locked","lock")=>"closed", _=>null
        };
        if(after is null)return before=="locked"?"Unlock the door before opening it.":"Invalid door operation.";
        if(before=="open"&&after!="open")
        {
            foreach(var agent in session.LifeDefinition.GetProperty("agents").EnumerateArray())
            {
                if(session.Placement(agent.GetProperty("id").GetString()!) is not { } actor ||
                   actor.Y>=doorway.Y+doorway.Height||actor.Y+1.75<=doorway.Y)continue;
                double x=actor.X-doorway.X,z=actor.Z-doorway.Z;
                if(Math.Abs(x*doorway.Ux+z*doorway.Uz)<=doorway.Width/2+0.18&&
                   Math.Abs(-x*doorway.Uz+z*doorway.Ux)<=doorway.Thickness/2+0.22)
                    return "Someone is in the doorway.";
            }
        }
        if(after=="open")doorStates.Remove(id);else doorStates[id]=after;
        BindObjectRouteProbe();
        System.IO.File.AppendAllText(System.IO.Path.Combine(auditDirectory,"session-events.jsonl"),
            Encode(new {kind="door",id,before,after,time=session.ContentTime})+"\n");
        return "";
    }
    public string Save(string path)
    {
        if(session is null||definition is null)return "The simulation has not started.";
        try
        {
            var destination=ProjectSettings.GlobalizePath(path);
            var temporary=destination+".tmp";
            System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(destination)!);
            System.IO.File.WriteAllText(temporary,Encode(new {hash=definition.Hash,state=session.SaveState(),receipts,notes,building=session.LifeDefinition.GetProperty("building"),game_time=session.ContentTime,content_path=contentPath,source=sourceManifest,custom_building=customBuilding,multilevel,door_states=doorStates}));
            System.IO.File.Move(temporary,destination,true);
            return "";
        }
        catch(Exception exception){return exception.Message;}
    }

    public string Load(string path)
    {
        try
        {
            using var document=JsonDocument.Parse(Read(path));var root=document.RootElement;
            var source=root.TryGetProperty("source",out var storedSource)?storedSource.GetString()!:sourceManifest;
            var layered=root.TryGetProperty("multilevel",out var storedLevel)&&storedLevel.GetBoolean();
            var restoredDefinition=root.TryGetProperty("source",out _)?Prepare(source,root.TryGetProperty("custom_building",out var custom)&&custom.GetBoolean()?root.GetProperty("building").GetRawText():"",layered):definition??Prepare(Read(contentPath),"");
            if(restoredDefinition is null||root.GetProperty("hash").GetString()!=restoredDefinition.Hash)return "This save requires a compatible content version or a new session.";
            var replacement=restoredDefinition.Create();replacement.RestoreState(root.GetProperty("state").Deserialize<RuntimeSessionState>()!);
            var restoredDoorways=ReadDoorways(replacement.LifeDefinition.GetProperty("building"));
            var restoredDoors=root.TryGetProperty("door_states",out var persistedDoors)
                ?persistedDoors.Deserialize<Dictionary<string,string>>()??throw new InvalidDataException("Invalid saved door states.")
                :new Dictionary<string,string>(StringComparer.Ordinal);
            if(restoredDoors.Any(item=>!restoredDoorways.ContainsKey(item.Key)||item.Value is not ("closed" or "locked")))
                throw new InvalidDataException("Invalid saved door states.");
            var restoredReceipts=root.TryGetProperty("receipts",out var savedReceipts)?savedReceipts.Deserialize<ActionReceipt[]>()!:[];
            var restoredNotes=root.TryGetProperty("notes",out var storedNotes)?JsonNode.Parse(storedNotes.GetRawText())!.AsObject():new JsonObject();
            var restoredDecisions=new Dictionary<long,Decision>();
            foreach(var execution in replacement.SaveState().Executions)
                if(replacement.DecisionFor(execution.Execution) is { } decision)restoredDecisions.Add(execution.Execution,decision);
            var destination=auditDirectory.Length>0?auditDirectory:ProjectSettings.GlobalizePath("res://.runtime/life-sessions/"+Guid.NewGuid().ToString("N"));
            System.IO.Directory.CreateDirectory(destination);
            System.IO.File.AppendAllText(System.IO.Path.Combine(destination,"session-events.jsonl"),Encode(new {kind="load",path,time=replacement.ContentTime,hash=restoredDefinition.Hash})+"\n");
            session=replacement;definition=restoredDefinition;sourceManifest=source;auditDirectory=destination;error="";
            multilevel=layered;doorways=restoredDoorways;doorStates=restoredDoors;
            customBuilding=root.TryGetProperty("custom_building",out var restoredCustom)&&restoredCustom.GetBoolean();
            if(root.TryGetProperty("content_path",out var savedPath))contentPath=savedPath.GetString()!;
            decisions.Clear();foreach(var item in restoredDecisions)decisions.Add(item.Key,item.Value);
            receipts.Clear();receipts.AddRange(restoredReceipts);disabledReasons.Clear();notes=restoredNotes;
            return "";
        }
        catch(Exception exception){return exception.Message;}
    }
    public string Reload(string path)
    {
        if(session is null||definition is null)return "The simulation has not started.";
        try
        {
            var replacement=new CharacterSessionDefinition(Read(path),Read("res://assets/data/98-runtime-session.data.dv"),Read);
            var saved=session.SaveState();
            CharacterContentRevisions.ValidateDeclarations(definition.Declaration,replacement.Declaration,saved);
            var restored=replacement.Create();restored.RestoreState(saved);
            CharacterContentRevisions.AssertStatePreserved(saved,restored.SaveState());
            var newDoorways=ReadDoorways(restored.LifeDefinition.GetProperty("building"));
            if(doorStates.Keys.Any(id=>!newDoorways.ContainsKey(id)))throw new InvalidDataException("Reload would lose door state.");
            definition=replacement;session=restored;contentPath=path;sourceManifest=Read(path);customBuilding=false;
            doorways=newDoorways;
            BindObjectRouteProbe();
            decisions.Clear();
            foreach(var execution in saved.Executions)
                if(session.DecisionFor(execution.Execution) is { } decision)decisions.Add(execution.Execution,decision);
            return "";
        }
        catch(Exception exception){return "Reload failed; the current session was kept: "+exception.Message;}
    }
    public void Close()
    {
        if(session is null)return;
        System.IO.File.WriteAllText(System.IO.Path.Combine(auditDirectory,"final.json"),Observe());session=null;decisions.Clear();objectRoutes.Clear();objectRouteSpace=null;objectRouteActions=null;
    }
    public override void _ExitTree()=>Close();
}
