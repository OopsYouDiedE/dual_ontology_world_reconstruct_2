using System.Text.Json;
using System.Text.Json.Nodes;
using DuelView.Dv;

namespace DuelView.Runtime;

public static class LifeScenario
{
    internal static JsonElement Read(string path,string identity,Func<string,string> read)=>
        DvDocument.Parse(read(path)).Definition("data",identity).GetProperty("value");
    internal static JsonNode? Copy(JsonElement value)=>value.ValueKind==JsonValueKind.Undefined?null:JsonNode.Parse(value.GetRawText());
    internal static JsonObject Object(object value)=>JsonSerializer.SerializeToNode(value)!.AsObject();
    internal static JsonObject Ref(string path)
    {
        var key=RuntimeSession.PathKey(path);
        return Object(new {type="ref",@object=key.Object,facet=key.Facet,field=key.Field});
    }
    internal static JsonObject AtLeast(string path,double value)=>new(){["op"]="at_least",["ref"]=Ref(path),["value"]=value};
    internal static JsonObject All(params JsonNode[] conditions)=>new(){["op"]="all",["items"]=new JsonArray(conditions.Select(condition=>condition.DeepClone()).ToArray())};
    public static JsonElement Expand(JsonElement manifest,Func<string,string> read)
    {
        if(manifest.Get("life_source").Text().Length==0)return manifest;
        var rules=Read(manifest.Get("life_source").Text(),"runtime.life",read);
        var cognition=Read(rules.Get("cognition_source").Text(),"runtime.life_cognition",read);
        var building=Read(manifest.Get("building_source").Text(),"life.building",read);
        var roots=building.Get("layers").Items().Where(layer=>layer.Get("roomFaces").Items().Any()).ToArray();
        if(roots.Length==0)throw new InvalidDataException("生活建筑缺少封闭房间。");
        var layer=roots[0];var height=layer.Get("y").Number();
        var rooms=layer.Get("roomFaces").Items().ToArray();
        var props=building.Get("props").Items().Where(prop=>Math.Abs(prop.Get("y").Number()-height)<0.6).ToArray();
        if(props.Select(prop=>prop.Get("id").Text()).Distinct().Count()!=props.Length)throw new InvalidDataException("生活建筑家具 ID 重复。");
        var life=JsonNode.Parse(rules.GetRawText())!.AsObject();
        life["building"]=Copy(building);life["layer_y"]=height;
        life["senses"]=Copy(cognition.Get("senses"));
        life["rooms"]=new JsonArray(rooms.Select(Copy).ToArray());
        var objects=new JsonArray();var facts=new JsonObject();var slots=new JsonArray();
        var root=JsonNode.Parse(manifest.GetRawText())!.AsObject();
        root["compact"]=true;root["life"]=life;root["facts"]=facts;root["slots"]=slots;
        root["clock_ref"]=Ref("clock.minutes");
        root["room_labels"]=new JsonObject{["house"]="生活宅邸"};root["cost_model"]=new JsonObject();
        root["scheduling"]=Object(new {decision_interval_seconds=30,actor_stagger_seconds=2,candidates_per_decision=24,evaluations_per_slice=16,milliseconds_per_slice=3});
        var inventory=rules.Get("inventory");
        facts["clock.minutes"]=manifest.Get("start_minutes").Number();
        facts["life.supplied"]=0;facts["life.consumed"]=0;facts["life.supply_day"]=-1;
        facts["life.rng"]=rules.Get("response").Get("initial_seed").Number(7);
        facts["life.contracts"]=new JsonArray();facts["life.seating"]=new JsonArray();facts["life.last_decay"]=manifest.Get("start_minutes").Number();facts["life.last_sense"]=manifest.Get("start_minutes").Number();
        var supplied=0.0;
        foreach(var prop in props)
        {
            var id=prop.Get("id").Text();var kind=prop.Get("kind").Text();
            var zone=Zone(rooms,prop.Get("x").Number(),prop.Get("z").Number());
            var capacity=(int)rules.Get("capacities").Get(kind).Number(1);
            objects.Add(Object(new {id,kind,zone,x=prop.Get("x").Number(),z=prop.Get("z").Number(),y=height,yaw=prop.Get("yaw").Number(),capacity}));
            for(var slot=0;slot<capacity;slot++)slots.Add(Object(new {id="life.slot."+id+"."+slot,capacity=1}));
            var stock=kind=="cabinet"?inventory.Get("initial_per_pantry").Number():0;
            facts[id+".stock"]=stock;facts[id+".lamp"]=false;facts[id+".occupants"]=new JsonArray();supplied+=stock;
        }
        life["objects"]=objects;
        var authored=Read(rules.Get("character_source").Text(),"runtime.character_session",read);
        var actors=new JsonArray();var actorIds=rules.Get("agents").Items().Select(agent=>agent.Get("id").Text()).ToArray();
        if(actorIds.Length!=5||actorIds.Distinct().Count()!=actorIds.Length)throw new InvalidDataException("生活场景需要五个不同人物。");
        var homeIndex=0;
        foreach(var profile in rules.Get("agents").Items())
        {
            var id=profile.Get("id").Text();var home=homeIndex++%rooms.Length;
            var centroid=rooms[home].Get("centroid").Items().Select(value=>value.Number()).ToArray();
            facts[id+".room"]="house";facts[id+".zone"]=home;facts[id+".food"]=inventory.Get("initial_carried").Number();
            facts[id+".book"]=false;facts[id+".noise_until"]=0;facts[id+".quiet_until"]=0;
            facts[id+".seat_plan"]="";
            facts[id+".x"]=centroid[0];facts[id+".z"]=centroid[1];
            supplied+=inventory.Get("initial_carried").Number();
            var knows=new JsonObject{[id+".room"]="house",[id+".zone"]=home,[id+".food"]=inventory.Get("initial_carried").Number(),[id+".book"]=false};
            foreach(var field in new[]{"personal_purpose","professional_memory"})
            {
                var key=id+".doc."+field;var value=authored.Get("facts").Get(key);
                if(value.ValueKind!=JsonValueKind.String)throw new InvalidDataException("缺少正式人物初始认知："+key);
                facts[key]=Copy(value);knows[key]=Copy(value);
            }
            var needs=JsonNode.Parse(rules.Get("initial_needs").GetRawText())!.AsObject();
            var motivation=authored.Get("actors").Items().Single(actor=>actor.Get("id").Text()==id).Get("autonomy");
            var decay=new JsonObject();var weights=new JsonObject();
            foreach(var need in rules.Get("needs").Fields())
            {
                var sourced=need.Value.Get("character_source").Flag();
                if(sourced)needs[need.Name]=motivation.Get("commodity_needs").Get(need.Name).Number();
                decay[need.Name]=sourced?motivation.Get("need_decay_per_second").Get(need.Name).Number():need.Value.Get("decay").Number()/60;
                weights[need.Name]=sourced?motivation.Get("autonomy_weights").Get(need.Name).Number(1):profile.Get("weights").Get(need.Name).Number(1);
            }
            var actions=new JsonArray();
            foreach(var definition in rules.Get("actions").Fields())
            foreach(var item in objects.OfType<JsonObject>().Where(item=>definition.Value.Get("kinds").Items().Any(kind=>kind.Text()==item["kind"]!.GetValue<string>())))
            for(var slot=0;slot<item["capacity"]!.GetValue<int>();slot++)
            {
                var action=definition.Value;var objectId=item["id"]!.GetValue<string>();
                var duration=action.Get("dur").Items().Select(value=>value.Number()).DefaultIfEmpty(10).Average();
                var effects=new JsonObject();foreach(var effect in action.Get("fx").Fields())effects[effect.Name]=Math.Clamp(effect.Value.Number()*duration,-80,80);
                foreach(var effect in profile.Get("action_motives").Get(definition.Name).Fields())effects[effect.Name]=effect.Value.Number();
                var when=new JsonObject();var requires=new JsonArray();var increments=new JsonObject();var writes=new JsonObject{[id+".zone"]=item["zone"]!.DeepClone()};
                if(action.Get("requires").Text()=="food"){when[id+".food"]=1;requires.Add(AtLeast(id+".food",1));}
                if(action.Get("requires").Text()=="book")when[id+".book"]=true;
                if(action.Get("requires_not").Text()=="food")when[id+".food"]=0;
                if(action.Get("requires_not").Text()=="book")when[id+".book"]=false;
                if(action.Get("gives").Text()=="food")
                {requires.Add(AtLeast(objectId+".stock",1));increments[objectId+".stock"]=-1;increments[id+".food"]=1;}
                if(action.Get("consumes").Text()=="food"){increments[id+".food"]=-1;increments["life.consumed"]=1;}
                if(action.Get("gives").Text()=="book")writes[id+".book"]=true;
                if(action.Get("consumes").Text()=="book")writes[id+".book"]=false;
                if(action.Get("special").Text().Length>0)writes[objectId+".lamp"]=action.Get("special").Text()=="lamp_on";
                var predicted=effects.DeepClone().AsObject();
                foreach(var gain in action.Get("chain_gain").Fields())predicted[gain.Name]=gain.Value.Number();
                var spec=Object(new {id=id+".life."+definition.Name+"."+objectId+"."+slot,label=action.Get("label").Text(),kind="life",minutes=duration,
                    focus=objectId,offscreen_approach_seconds=rules.Get("time").Get("logical_approach_seconds").Number(),cooldown_minutes=action.Get("cooldown").Number(2),completion_text=action.Get("label").Text(),
                    life=new {action=definition.Name,obj=objectId,slot},motor=new {posture=action.Get("pose").Text(),animation=definition.Name,target=new[]{item["x"]!.GetValue<double>(),height,item["z"]!.GetValue<double>()}}});
                spec["when"]=when;spec["requires"]=All(requires.Select(value=>value!).ToArray());
                spec["writes"]=writes;spec["increments"]=increments;
                spec["observes"]=new JsonArray(new[]{id+".zone",id+".food",id+".book"}.Concat(action.Get("reveals").Items().Select(field=>objectId+"."+field.Text())).Select(value=>(JsonNode)JsonValue.Create(value)!).ToArray());
                spec["reserve"]=new JsonArray("life.slot."+objectId+"."+slot);
                spec["completed_need_effects"]=effects;spec["perceived_need_effects"]=predicted;
                var below=Copy(action.Get("when")) as JsonObject??new();
                if(effects.Count>0&&below.Count==0&&!action.Get("commitment_only").Flag())foreach(var effect in effects.Where(effect=>effect.Value!.GetValue<double>()>0))below[effect.Key]=rules.Get("brain").Get("satisfied_below").Number();
                if(below.Count>0&&action.Get("when_night").ValueKind==JsonValueKind.Undefined)spec["need_below"]=below;
                actions.Add(spec);
            }
            foreach(var other in actorIds.Where(other=>other!=id))
            foreach(var category in rules.Get("social").Get("categories").Fields())
            foreach(var fulfil in new[]{false,true})
            {
                var spec=Object(new {id=id+".life."+(fulfil?"fulfil":"request")+"."+category.Name+"."+other,label=(fulfil?"履行承诺：":"")+category.Value.Get("label").Text(),
                    kind="life",minutes=category.Value.Get("minutes").Number(rules.Get("response").Get("request_minutes").Number()),focus=other,offscreen_approach_seconds=rules.Get("time").Get("logical_social_approach_seconds").Number(),cooldown_minutes=rules.Get("response").Get("cooldown_minutes").Number(),
                    life=new {action=fulfil?"fulfil":"request",target=other,category=category.Name},
                    perceived_need_effects=category.Value.Get("need"),completed_need_effects=new {},motor=new {posture="stand",animation="talk"}});
                var predicted=spec["perceived_need_effects"]!.AsObject();
                var cognitionGate=new JsonObject{[other+".trace.in_view"]=true};
                var cognitiveField=cognition.Get("social_requirements").Get(category.Name).Text();
                if(!fulfil&&cognitiveField.Length>0)cognitionGate[other+".infer."+cognitiveField]="proved";
                spec["because"]=cognitionGate;
                foreach(var gain in profile.Get("social_motives").Get(category.Name).Fields())predicted[gain.Name]=gain.Value.Number();
                spec["reserve"]=new JsonArray("life.social."+id,"life.social."+other);
                actions.Add(spec);
            }
            actors.Add(new JsonObject{["id"]=id,["label"]=profile.Get("name").Text(),["autonomous"]=true,["knows"]=knows,["actions"]=actions,
                ["cognition"]=LifeCognitionScenario.Expand(cognition,id,actorIds),
                ["autonomy"]=new JsonObject{["commodity_needs"]=needs,["need_decay_per_second"]=decay,["autonomy_weights"]=weights,["score_scale"]=1,["time_cost"]=0.0005},
                ["policy"]=new JsonObject{["goals"]=new JsonArray()}});
        }
        facts["life.supplied"]=supplied;
        foreach(var from in actorIds)foreach(var to in actorIds.Where(to=>to!=from))
        {
            var pair="relation:"+from+":"+to;
            foreach(var axis in rules.Get("relationship").Get("initial").Fields())facts[pair+"."+axis.Name]=Copy(axis.Value);
            facts[pair+".day"]=-1;facts[pair+".up"]=new JsonObject();facts[pair+".down"]=new JsonObject();facts[pair+".habit"]=new JsonObject();facts[pair+".stage"]="生疏";
        }
        root["actors"]=actors;root.Remove("life_source");root.Remove("building_source");
        LifeCognitionScenario.Acceptance(root,cognition,actorIds);
        return JsonSerializer.SerializeToElement(root);
    }
    internal static int Zone(JsonElement[] rooms,double positionX,double positionZ)
    {
        for(var room=0;room<rooms.Length;room++)
        {
            var polygon=rooms[room].Get("polygon").Items().ToArray();var inside=false;
            for(var index=0;index<polygon.Length;index++)
            {
                var first=polygon[index].Items().Select(value=>value.Number()).ToArray();
                var second=polygon[(index+1)%polygon.Length].Items().Select(value=>value.Number()).ToArray();
                if((first[1]>positionZ)!=(second[1]>positionZ)&&positionX<(second[0]-first[0])*(positionZ-first[1])/(second[1]-first[1])+first[0])inside=!inside;
            }
            if(inside)return room;
        }
        return -1;
    }
}
