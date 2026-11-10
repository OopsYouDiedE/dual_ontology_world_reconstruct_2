using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Runtime;

/// <summary>Generic DV authoring shorthand. Story, evidence, routes and timings remain in DV.</summary>
internal static class CompactScenario
{
    static JsonNode? Copy(JsonNode? value)=>value?.DeepClone();
    static JsonObject Ref(string path)
    {
        var i=path.LastIndexOf('.');if(i<1)throw new InvalidDataException("Expected object[.facet].field: "+path);
        var prefix=path[..i];var j=prefix.LastIndexOf('.');
        var explicitFacet=j>0&&prefix[(j+1)..] is "state" or "phys" or "trace" or "lock" or "doc" or "infer";
        return new(){["type"]="ref",["object"]=explicitFacet?prefix[..j]:prefix,["facet"]=explicitFacet?prefix[(j+1)..]:"state",["field"]=path[(i+1)..]};
    }
    static JsonObject Eq(string path,JsonNode? value)=>new(){["op"]="equals",["ref"]=Ref(path),["value"]=Copy(value)};
    static JsonObject Known(string path)=>new(){["op"]="known",["ref"]=Ref(path)};
    static JsonObject Not(JsonNode value)=>new(){["op"]="not",["item"]=value};
    static JsonObject All(JsonArray items)=>new(){["op"]="all",["items"]=items};
    static JsonArray List(JsonNode? value)=>value as JsonArray??[];
    static JsonObject Map(JsonNode? value)=>value as JsonObject??new();
    static JsonObject Merge(JsonObject defaults,JsonObject overrides)
    {
        var result=(JsonObject)defaults.DeepClone();
        foreach(var p in overrides)result[p.Key]=result[p.Key] is JsonObject old&&p.Value is JsonObject next?Merge(old,next):Copy(p.Value);
        return result;
    }
    static JsonArray References(JsonNode? value)=>new(List(value).Select(v=>(JsonNode)Ref(v!.GetValue<string>())).ToArray());
    static JsonArray Conditions(JsonNode? value)=>value is JsonObject condition&&condition.ContainsKey("op")
        ?new JsonArray(condition.DeepClone()):new(Map(value).Select(p=>(JsonNode)Eq(p.Key,p.Value)).ToArray());
    static JsonArray Effects(JsonNode? value)=>new(Map(value).Select(p=>(JsonNode)new JsonObject{["op"]="assign",["ref"]=Ref(p.Key),["value"]=Copy(p.Value)}).ToArray());
    internal static JsonNode ExpandPlanning(JsonNode value)
    {
        var result=value.DeepClone().AsObject();
        JsonNode ConditionNode(JsonNode? condition)=>condition is JsonObject obj&&obj.ContainsKey("op")?obj.DeepClone():All(Conditions(condition));
        foreach(var task in List(result["tasks"]))
        {
            if(task is not JsonObject t)throw new InvalidDataException("Task declaration must be an object.");
            if(t["available_when"] is null||t["goal"] is null)throw new InvalidDataException("Task requires knowledge admission and completion.");
            t["available_when"]=ConditionNode(t["available_when"]);t["goal"]=ConditionNode(t["goal"]);
            foreach(var step in List(t["steps"]))
            {
                if(step is not JsonObject s||s["done_when"] is null)throw new InvalidDataException("Plan steps require an observed completion condition.");
                s["done_when"]=ConditionNode(s["done_when"]);
            }
        }
        foreach(var route in List(result["physiology"]?["routes"]))
        {
            if(route is not JsonObject r||r["available_when"] is null)throw new InvalidDataException("A physiological route requires a knowledge admission condition.");
            r["available_when"]=ConditionNode(r["available_when"]);
        }
        return result;
    }
    internal static JsonNode ExpandGoalPlanning(JsonNode value)
    {
        var result=value.DeepClone().AsObject();
        if(result["when"] is not null)result["when"]=All(Conditions(result["when"]));
        foreach(var goal in List(result["goals"]))
        {
            if(goal is not JsonObject g||g["target"] is null)throw new InvalidDataException("A personal goal needs an explicit desired condition.");
            g["target"]=All(Conditions(g["target"]));
            g["when"]=All(Conditions(g["when"]));
        }
        return result;
    }
    static void Put(JsonObject objects,string path,JsonNode? value)
    {
        var r=Ref(path);var id=r["object"]!.GetValue<string>();var field=r["field"]!.GetValue<string>();
        objects[id]??=new JsonObject{["facets"]=new JsonObject{["state"]=new JsonObject()}};
        var facet=r["facet"]!.GetValue<string>();
        objects[id]!["facets"]![facet]??=new JsonObject();
        objects[id]!["facets"]![facet]![field]=new JsonObject{["value"]=Copy(value),["known"]=true,["confidence"]=1};
    }
    static JsonNode? Substitute(JsonNode? node,JsonObject arguments)
    {
        if(node is JsonValue v && v.TryGetValue<string>(out var text))
        {foreach(var p in arguments)text=text.Replace("${"+p.Key+"}",p.Value is JsonValue x&&x.TryGetValue<string>(out var s)?s:p.Value?.ToJsonString()??"");return JsonValue.Create(text);}
        if(node is JsonObject o){var result=new JsonObject();foreach(var p in o)result[Substitute(JsonValue.Create(p.Key),arguments)!.GetValue<string>()]=Substitute(p.Value,arguments);return result;}
        if(node is JsonArray a)return new JsonArray(a.Select(n=>Substitute(n,arguments)).ToArray());
        return Copy(node);
    }
    public static JsonElement Expand(JsonElement raw)
    {
        if(!raw.Get("compact").Flag())return raw.Clone();
        var root=JsonNode.Parse(raw.GetRawText())!.AsObject();var objects=new JsonObject();var laws=new JsonObject();var slots=new HashSet<string>();
        var capacities=new Dictionary<string,int>(StringComparer.Ordinal);
        foreach(var slot in List(root["slots"]))
        {
            var slotId=slot?["id"]?.GetValue<string>()??"";
            if(string.IsNullOrWhiteSpace(slotId)||slot?["capacity"] is not JsonValue capacity||!capacity.TryGetValue<int>(out var count)||count<1||!capacities.TryAdd(slotId,count))
                throw new InvalidDataException("Invalid or duplicate compact reservation slot: "+slotId);
        }
        var actionIds=new HashSet<string>(StringComparer.Ordinal);
        foreach(var p in Map(root["facts"]))Put(objects,p.Key,p.Value);
        var templates=Map(root["templates"]);var defaults=Map(root["actor_defaults"]);
        foreach(var entry in List(root["actors"]))
        {
            var actor=entry!.AsObject();var id=actor["id"]!.GetValue<string>();
            if(actor["autonomy"] is JsonObject overrides)actor["autonomy"]=Merge(Map(defaults["autonomy"]),overrides);
            foreach(var p in defaults)if(!actor.ContainsKey(p.Key))actor[p.Key]=Copy(p.Value);
            var mindObjects=new JsonObject();foreach(var p in Map(actor["knows"]))Put(mindObjects,p.Key,p.Value);
            foreach(var sensor in List(actor["perceptions"]))
            {
                sensor!["condition"]=All(Conditions(sensor["when"]));
                sensor["knowledge_condition"]=All(Conditions(sensor["knows"]));
                sensor["refs"]=References(sensor["observes"]);
            }
            var inferences=new JsonObject();var ruleIndex=0;
            foreach(var rule in List(actor["rules"]))inferences["rule."+(++ruleIndex)]=new JsonObject{["mode"]="infer",["basis"]=Copy(rule!["basis"]),["law"]=new JsonObject{["premise"]=All(Conditions(rule["when"])),["effects"]=Effects(rule["then"])}};
            var actions=new JsonArray();
            foreach(var spec in List(actor["actions"]))
            {
                JsonObject a;
                if(spec!["use"] is { } use)
                {
                    var args=Map(Copy(actor["args"]));args["actor"]=id;
                    foreach(var p in Map(spec["args"]))args[p.Key]=Copy(p.Value);
                    a=Substitute(templates[use.GetValue<string>()]??throw new InvalidDataException("Unknown action template."),args)!.AsObject();
                    foreach(var p in spec.AsObject().Where(p=>p.Key is not ("use" or "args")))a[p.Key]=Substitute(p.Value,args);
                }
                else a=(JsonObject)Copy(spec)!;
                var actionId=a["id"]!.GetValue<string>();
                if(string.IsNullOrWhiteSpace(actionId)||!actionIds.Add(actionId))throw new InvalidDataException("Missing or duplicate expanded action: "+actionId);
                var gate=Conditions(a["when"]);var objective=Conditions(a["requires"]);
                var recognition=a["recognize_when"] is null?null:Conditions(a["recognize_when"]);
                foreach(var reason in Conditions(a["because"]))gate.Add(Copy(reason));
                if(actor["wake_at_game_minutes"] is not null&&actionId!=id+".wake")
                {gate.Add(Eq("event:"+id+".wake.done",JsonValue.Create(true)));recognition?.Add(Eq("event:"+id+".wake.done",JsonValue.Create(true)));}
                if(a["at"] is { } room){gate.Add(Eq(id+".room",room));objective.Add(Eq(id+".room",room));}
                foreach(var unknown in List(a["unknown"]))
                {gate.Add(Not(Known(unknown!.GetValue<string>())));recognition?.Add(Not(Known(unknown.GetValue<string>())));}
                var effects=Effects(a["writes"]);var grants=References(a["observes"]);
                foreach(var change in Map(a["increments"]))
                {
                    if(change.Value is not JsonValue amount||!amount.TryGetValue<double>(out var number)||!double.IsFinite(number))
                        throw new InvalidDataException("A resource increment must be a finite number: "+actionId);
                    if(Map(a["writes"]).ContainsKey(change.Key))throw new InvalidDataException("An action cannot assign and increment the same field: "+actionId);
                    effects.Add(new JsonObject{["op"]="increment",["ref"]=Ref(change.Key),["value"]=Copy(change.Value)});
                }
                foreach(var write in Map(a["writes"]).Concat(Map(a["increments"])))
                {
                    var target=Ref(write.Key)["object"]!.GetValue<string>();
                    objects[target]??=new JsonObject{["facets"]=new JsonObject{["state"]=new JsonObject()}};
                }
                if(a["once"]?.GetValue<bool>()==true)
                {
                    var key="event:"+actionId+".done";Put(objects,key,JsonValue.Create(false));
                    gate.Add(Not(Known(key)));recognition?.Add(Not(Known(key)));objective.Add(Eq(key,JsonValue.Create(false)));
                    effects.Add(new JsonObject{["op"]="assign",["ref"]=Ref(key),["value"]=true});grants.Add(Ref(key));
                }
                laws[actionId]=new JsonObject{["mode"]="enforce",["law"]=new JsonObject{["premise"]=All(objective),["effects"]=effects}};
                a["precondition"]=All(gate);a["law"]=actionId;a["grants"]=grants;
                if(recognition is not null)a["recognize_when"]=All(recognition);
                if(a["planning_model"] is JsonObject model)
                {
                    model["when"]=All(Conditions(model["when"]));
                    var predictions=model["effects"] is JsonArray explicitEffects?explicitEffects.DeepClone().AsArray():Effects(model["effects"]);
                    foreach(var prediction in Map(model["increments"]))
                        predictions.Add(new JsonObject{["op"]="increment",["ref"]=Ref(prediction.Key),["value"]=Copy(prediction.Value)});
                    if(a["once"]?.GetValue<bool>()==true&&!predictions.Any(prediction=>JsonNode.DeepEquals(prediction?["ref"],Ref("event:"+actionId+".done"))))
                        predictions.Add(new JsonObject{["op"]="assign",["ref"]=Ref("event:"+actionId+".done"),["value"]=true});
                    model["effects"]=predictions;model.Remove("increments");
                }
                a["duration_seconds"]=(a["minutes"]?.GetValue<double>()??1)*60;
                a["resource_reservations"]=Copy(a["reserve"])??new JsonArray();
                var reservations=a["resource_reservations"]!.AsArray();reservations.Add("actor."+id);
                if(root["atomic_actions"]?.GetValue<bool>()==true&&a["focus"] is not JsonValue)
                    throw new InvalidDataException("Atomic action requires one primary focus: "+actionId);
                if(a["interaction_slot"] is JsonValue interactionSlot)reservations.Add("interaction."+interactionSlot.GetValue<string>());
                foreach(var r in reservations)slots.Add(r!.GetValue<string>());
                var tells=new JsonArray();
                foreach(var tell in List(a["tell"]))
                {
                    var h=new JsonObject{["actor"]=Copy(tell!["actor"]),["refs"]=References(tell["fields"]),["result_refs"]=References(tell["results"])};
                    var audience=Conditions(tell["when"]);
                    if(tell["room"] is { } location)audience.Add(Eq(tell["actor"]!.GetValue<string>()+".room",location));
                    if(tell["rooms"] is JsonArray locations)audience.Add(Not(All(new JsonArray(locations.Select(room=>(JsonNode)Not(Eq(tell["actor"]!.GetValue<string>()+".room",room))).ToArray()))));
                    if(audience.Count>0)h["only_if"]=All(audience);
                    tells.Add(h);
                }
                a["handoffs"]=tells;
                var availability=Conditions(a["requires"]);
                foreach(var condition in Conditions(a["authority"]))availability.Add(Copy(condition));
                if(availability.Count>0)a["authority_precondition"]=All(availability);
                foreach(var key in new[]{"when","requires","writes","increments","observes","minutes","at","unknown","once","reserve","tell","authority"})a.Remove(key);
                actions.Add(a);
            }
            actor["actions"]=actions;actor["mind"]=new JsonObject{["subject"]=id,["objects"]=mindObjects,["adoptions"]=inferences};
            if(actor["planning"] is JsonObject planning)actor["planning"]=ExpandPlanning(planning);
            if(actor["goal_planning"] is JsonObject goalPlanning)actor["goal_planning"]=ExpandGoalPlanning(goalPlanning);
        }
        root["physical"]=new JsonObject{["subject"]="world",["time"]=Copy(root["start_minutes"]),["objects"]=objects,["adoptions"]=laws};
        root["slots"]=new JsonArray(slots.Concat(capacities.Keys).Distinct(StringComparer.Ordinal).Select(s=>(JsonNode)new JsonObject{["id"]=s,["capacity"]=capacities.GetValueOrDefault(s,1)}).ToArray());
        var bindings=new JsonArray();foreach(var actor in List(root["actors"]))foreach(var p in objects)bindings.Add(new JsonObject{["subject"]=Copy(actor!["id"]),["physical"]=p.Key,["local"]=p.Key});root["bindings"]=bindings;
        foreach(var key in new[]{"templates","actor_defaults","facts","compact"})root.Remove(key);
        return JsonSerializer.SerializeToElement(root);
    }
}
