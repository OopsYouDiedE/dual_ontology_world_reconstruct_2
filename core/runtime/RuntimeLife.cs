using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Runtime;

public sealed partial class RuntimeSession
{
    private JsonElement lifeDefinition;
    public JsonElement LifeDefinition=>lifeDefinition;
    public bool IsLifeSession=>lifeDefinition.ValueKind==JsonValueKind.Object;
    private double LifeNumber(string path)=>World.Read(PathKey(path))?.Value.Number()??0;
    private JsonElement LifeValue(string path)=>World.Read(PathKey(path))?.Value??default;
    private Fact LifeFact(object value)=>new(JsonSerializer.SerializeToElement(value),true,false,1,ContentTime,0);
    private static string Pair(string from,string to)=>"relation:"+from+":"+to;
    private bool LifeWorking(string actor)=>running.TryGetValue(actor,out var work)&&!work.CancelRequested&&!conversationHolds.ContainsKey(actor)&&work.WorkStartedAt.HasValue;
    public void ConfigureLife(JsonElement definition)
    {
        if(definition.ValueKind==JsonValueKind.Undefined)return;
        lifeDefinition=definition.Clone();
        foreach(var profile in definition.Get("agents").Items())
        {
            var id=profile.Get("id").Text();
            if(!actors.ContainsKey(id))throw new InvalidDataException("Unknown life actor: "+id);
            ReportPlacement(id,LifeNumber(id+".x"),definition.Get("layer_y").Number(),LifeNumber(id+".z"),0,"house");
        }
    }
    public void ConfigureLifeSeed(int seed)
    {
        if(!IsLifeSession)return;
        if(running.Count>0||mechanicHistory.Count>0)throw new InvalidOperationException("随机种子只能在新局设置。");
        Rules.Changed(World.Apply(new Dictionary<FieldKey,Fact>{{PathKey("life.rng"),LifeFact((uint)seed+1)}}));
    }
    private void LifeObserve(string actor,FieldKey key)
    {
        var client=actors[actor];var fact=World.Read(key);
        if(fact is not {Known:true,Conflicted:false}||client.Recall(key) is {Known:true,Conflicted:false} old&&Values.Same(old.Value,fact.Value))return;
        client.ReceiveSalient(new("life/"+actor+"/"+key+"/"+fact.Revision,key,fact.Value,fact.Confidence,ContentTime,InformationOrigin.Passive,
            JsonSerializer.SerializeToElement(new {actor,channel="life_sense",physical_field=key,world_revision=fact.Revision})));
    }
    private void AdvanceLife()
    {
        if(!IsLifeSession)return;
        var day=(int)(ContentTime/1440);var hour=ContentTime%1440/60;
        var writes=new Dictionary<FieldKey,Fact>();
        var inventory=lifeDefinition.Get("inventory");
        if(hour>=inventory.Get("supply_hour").Number()&&LifeNumber("life.supply_day")<day)
        {
            var remaining=inventory.Get("daily_supply").Number();var supplied=0.0;
            foreach(var pantry in lifeDefinition.Get("objects").Items().Where(item=>item.Get("kind").Text()=="cabinet"))
            {
                var key=pantry.Get("id").Text()+".stock";
                var amount=Math.Max(0,Math.Min(remaining,inventory.Get("capacity").Number()-LifeNumber(key)));
                writes[PathKey(key)]=LifeFact(LifeNumber(key)+amount);remaining-=amount;supplied+=amount;
            }
            writes[PathKey("life.supplied")]=LifeFact(LifeNumber("life.supplied")+supplied);
            writes[PathKey("life.supply_day")]=LifeFact(day);
            mechanicHistory.Add(new(ContentTime,0,"world","life.supply."+day,"life_supply",true,JsonSerializer.SerializeToElement(new {day,amount=supplied})));
        }
        var elapsed=ContentTime-LifeNumber("life.last_decay");
        if(elapsed>=60)
        {
            var parameters=lifeDefinition.Get("relationship");
            foreach(var from in actors.Keys)foreach(var to in actors.Keys.Where(to=>to!=from))
            {
                var pair=Pair(from,to);
                foreach(var axis in new[]{"tension","affinity"})
                {
                    var half=parameters.Get(axis+"_half_life_days").Number();
                    writes[PathKey(pair+"."+axis)]=LifeFact(LifeNumber(pair+"."+axis)*Math.Pow(0.5,elapsed/(half*1440)));
                }
                LifeStage(pair,writes);
            }
            writes[PathKey("life.last_decay")]=LifeFact(ContentTime);
        }
        var contracts=JsonNode.Parse(LifeValue("life.contracts").GetRawText())!.AsArray();var expired=false;
        foreach(var contract in contracts.OfType<JsonObject>().Where(contract=>contract["status"]!.GetValue<string>() is "pending" or "awaiting_seating"&&contract["expires"]!.GetValue<double>()<=ContentTime))
        {
            contract["status"]="expired";expired=true;
            LifeRelation(contract["target"]!.GetValue<string>(),contract["actor"]!.GetValue<string>(),"broken_promise",lifeDefinition.Get("relationship").Get("broken_effects"),writes);
            mechanicHistory.Add(new(ContentTime,0,contract["actor"]!.GetValue<string>(),contract["id"]!.GetValue<string>(),"life_contract",false,JsonSerializer.SerializeToElement(contract)));
        }
        if(expired)writes[PathKey("life.contracts")]=LifeFact(contracts);
        if(writes.Count>0)Rules.Changed(World.Apply(writes));
        AdvanceLifeSound();
        AdvanceLifeSeating();
        foreach(var actor in actors.Keys)
        {
            SenseLife(actor);
            if(!running.ContainsKey(actor)&&!actors[actor].IsUpdating&&!actors[actor].IsObserving)actors[actor].BeginRefresh(RefreshCause.Deliberate);
        }
        ValidateLifeInventory();
    }
    private void ValidateLifeInventory()
    {
        var amounts=lifeDefinition.Get("objects").Items().Select(item=>LifeNumber(item.Get("id").Text()+".stock"))
            .Concat(actors.Keys.Select(actor=>LifeNumber(actor+".food"))).ToArray();
        if(amounts.Any(amount=>!double.IsFinite(amount)||amount<0||amount!=Math.Truncate(amount))||
            Math.Abs(LifeNumber("life.supplied")-LifeNumber("life.consumed")-amounts.Sum())>0.000001)
            throw new InvalidDataException("生活库存不守恒或出现负数。");
    }
    private JsonElement LifeObject(string id)=>lifeDefinition.Get("objects").Items().FirstOrDefault(item=>item.Get("id").Text()==id);
    private void UpdateLifePlacement(string actor,double positionX,double positionZ)
    {
        if(!IsLifeSession)return;
        var zone=LifeScenario.Zone(lifeDefinition.Get("rooms").Items().ToArray(),positionX,positionZ);
        if(zone>=0&&LifeNumber(actor+".zone")!=zone)
            Rules.Changed(World.Apply(new Dictionary<FieldKey,Fact>{{PathKey(actor+".zone"),LifeFact(zone)}}));
    }
    private bool LifeLit(int zone)
    {
        var hour=ContentTime%1440/60;var time=lifeDefinition.Get("time");
        return hour>=time.Get("day_from").Number()&&hour<time.Get("dusk").Number()||
            lifeDefinition.Get("objects").Items().Any(item=>item.Get("zone").Number()==zone&&item.Get("kind").Text()=="wall_lantern"&&LifeValue(item.Get("id").Text()+".lamp").Flag());
    }
    private bool LifeEligible(string actor,ActionCandidate candidate)
    {
        var meta=candidate.Declaration.Get("life");if(meta.ValueKind!=JsonValueKind.Object)return true;
        var kind=meta.Get("action").Text();var target=meta.Get("target").Text();var client=actors[actor];
        var seatPlan=LifeSeatingFor(actor);
        if(kind=="join_seat")return seatPlan is { } plan&&plan.Get("participants").Items().Any(participant=>participant.Get("actor").Text()==actor&&participant.Get("obj").Text()==meta.Get("obj").Text()&&participant.Get("slot").Number()==meta.Get("slot").Number());
        if(seatPlan is not null)return false;
        if(kind is "request" or "fulfil")
        {
            if(client.Recall(new(target,"trace","in_view")) is not {Known:true,Conflicted:false} sight||!sight.Value.Flag())return false;
            var remembered=client.Recall(PathKey(target+".zone"));
            if(remembered is not {Known:true}||!Values.Same(remembered.Value,client.Recall(PathKey(actor+".zone"))?.Value??default))return false;
            var category=meta.Get("category").Text();var rule=lifeDefinition.Get("social").Get("categories").Get(category);
            if(kind=="fulfil")return LifeContract(actor,target,category) is { } contract&&contract.Get("status").Text()=="pending"&&ContentTime>=contract.Get("due").Number()&&
                (contract.Get("mode").Text()!="conditional"||Needs(actor).GetValueOrDefault("calm")>=lifeDefinition.Get("response").Get("calm_condition").Number());
            if(LifeContract(actor,target,category) is not null||LifeContract(target,actor,category) is not null)return false;
            if(category=="complain")return LifeProved(actor,target,"audible_source");
            if(category=="ask_share")return Needs(actor).GetValueOrDefault("hunger")<lifeDefinition.Get("response").Get("spontaneous_below").Number()&&(client.Recall(PathKey(actor+".food"))?.Value.Number()??1)==0&&LifeProved(actor,target,"can_request_food");
            if(category=="share_food")return (client.Recall(PathKey(actor+".food"))?.Value.Number()??0)>0&&LifeProved(actor,target,"may_need_food");
            if(category=="apologize")return LifeKnownNumber(actor,Pair(actor,target)+".tension")>=rule.Get("tension_above").Number();
            return rule.Get("need").Fields().Any(need=>Needs(actor).GetValueOrDefault(need.Name)<lifeDefinition.Get("response").Get("spontaneous_below").Number());
        }
        var definition=lifeDefinition.Get("actions").Get(kind);var item=LifeObject(meta.Get("obj").Text());
        if(item.ValueKind!=JsonValueKind.Object)return false;
        if(kind=="inspect_pantry")return client.Recall(PathKey(item.Get("id").Text()+".stock")) is not {Known:true,Conflicted:false} stock||stock.Value.Number()==0&&ContentTime-stock.ObservedAt>=lifeDefinition.Get("inventory").Get("inspect_retry_minutes").Number(60);
        var hour=ContentTime%1440/60;var timing=lifeDefinition.Get("time");
        var night=hour>=timing.Get("night_from").Number()||hour<timing.Get("night_to").Number();
        if(definition.Get("day_only").Flag()&&night)return false;
        if(definition.Get("when_night").ValueKind==JsonValueKind.Object&&
            definition.Get(night?"when_night":"day_when").Fields().Any(threshold=>Needs(actor).GetValueOrDefault(threshold.Name)>=threshold.Value.Number()))return false;
        if(client.Recall(PathKey(item.Get("id").Text()+".occupants")) is {Known:true} occupied&&occupied.Value.Items().Any(value=>value.Get("slot").Number()==meta.Get("slot").Number()&&value.Get("actor").Text()!=actor))return false;
        if(kind=="prepare_meal"&&(client.Recall(PathKey(item.Get("id").Text()+".stock"))?.Value.Number()??0)<1)return false;
        var zone=(int)item.Get("zone").Number();
        if((definition.Get("light").Flag()||definition.Get("needs_light").Flag())&&!LifeLitKnown(actor,zone))return false;
        if(kind=="light_lamp")return !LifeLitKnown(actor,zone);
        if(kind=="douse_lamp")return LifeLitKnown(actor,zone)&&ContentTime%1440/60>=lifeDefinition.Get("time").Get("night_from").Number();
        if(kind=="play_piano"&&LifeKnownNumber(actor,actor+".quiet_until")>ContentTime)return false;
        if(definition.Get("near").Items().Any()&&!lifeDefinition.Get("objects").Items().Any(other=>
            definition.Get("near").Items().Any(kind=>kind.Text()==other.Get("kind").Text())&&other.Get("zone").Number()==zone&&
            Math.Pow(other.Get("x").Number()-item.Get("x").Number(),2)+Math.Pow(other.Get("z").Number()-item.Get("z").Number(),2)<Math.Pow(definition.Get("near_dist").Number(),2)))return false;
        return true;
    }
    private bool LifeLitKnown(string actor,int zone)
    {
        var hour=ContentTime%1440/60;var timing=lifeDefinition.Get("time");
        if(hour>=timing.Get("day_from").Number()&&hour<timing.Get("dusk").Number())return true;
        return lifeDefinition.Get("objects").Items().Any(item=>item.Get("zone").Number()==zone&&item.Get("kind").Text()=="wall_lantern"&&
            actors[actor].Recall(PathKey(item.Get("id").Text()+".lamp"))?.Value.Flag()==true);
    }
    private JsonElement? LifeContract(string actor,string target,string category)=>LifeValue("life.contracts").Items().Cast<JsonElement?>().FirstOrDefault(value=>
        value!.Value.Get("actor").Text()==actor&&value.Value.Get("target").Text()==target&&value.Value.Get("category").Text()==category&&value.Value.Get("status").Text() is "pending" or "awaiting_seating");
    private bool LifeCanDeliver(string actor,string target,string category)
    {
        if(LifeNumber(actor+".zone")!=LifeNumber(target+".zone"))return false;
        if(running.TryGetValue(target,out var execution)&&lifeDefinition.Get("actions").Get(execution.Decision.Action.Declaration.Get("life").Get("action").Text()).Get("pose").Text()=="lie")return false;
        var effect=lifeDefinition.Get("social").Get("categories").Get(category).Get("fx").Text();
        if(effect=="share_food")return LifeNumber(actor+".food")>=1&&LifeNumber(target+".food")==0;
        if(effect is "hangout" or "yield_object")return LifeSeats(actor,target,effect).Length>0;
        if(effect=="offer_food")return LifeNumber(target+".food")>=1&&LifeNumber(actor+".food")==0;
        if(effect=="stop_noise")return LifeWorking(actor)&&LifeNumber(actor+".noise_until")>ContentTime;
        return true;
    }
    private Dictionary<string,double> LifeReply(string responder,string requester,string category,bool possible)
    {
        var response=lifeDefinition.Get("response");var pair=Pair(responder,requester);
        var profile=lifeDefinition.Get("agents").Items().First(item=>item.Get("id").Text()==responder);
        var rule=lifeDefinition.Get("social").Get("categories").Get(category);
        var terms=new Dictionary<string,double>{["affinity"]=LifeKnownNumber(responder,pair+".affinity")/100,["trust"]=LifeKnownNumber(responder,pair+".trust")/100,
            ["tension"]=LifeKnownNumber(responder,pair+".tension")/100,["cost"]=rule.Get("cost").Number(),["intrusion"]=rule.Get("intr").Number(),
            ["calm"]=Needs(responder).GetValueOrDefault("calm")/100,["agreeable"]=profile.Get("traits").Get("A").Number(),
            ["busy"]=running.ContainsKey(responder)?1:0,["debt"]=LifeKnownNumber(responder,pair+".owe"),["benefit"]=rule.Get("benefit").Number(rule.Get("weight").Number()),
            ["coercion"]=rule.Get("coercion").Number()};
        var result=new Dictionary<string,double>();
        foreach(var mode in response.Get("scores").Fields())
        {
            if(!possible&&mode.Name is "accept" or "comply")continue;
            result[mode.Name]=mode.Value.Get("base").Number()+mode.Value.Fields().Where(term=>term.Name!="base").Sum(term=>term.Value.Number()*terms.GetValueOrDefault(term.Name));
        }
        return result;
    }
    private void LifeRelation(string from,string to,string kind,JsonElement effects,Dictionary<FieldKey,Fact> writes)
    {
        var pair=Pair(from,to);var policy=lifeDefinition.Get("relationship");var day=(int)(ContentTime/1440);
        JsonElement Current(string axis)=>writes.GetValueOrDefault(PathKey(pair+"."+axis))?.Value??LifeValue(pair+"."+axis);
        var fresh=Current("day").Number()!=day;
        var up=fresh?new JsonObject():JsonNode.Parse(Current("up").GetRawText())!.AsObject();
        var down=fresh?new JsonObject():JsonNode.Parse(Current("down").GetRawText())!.AsObject();
        var habit=fresh?new JsonObject():JsonNode.Parse(Current("habit").GetRawText())!.AsObject();
        var count=habit[kind]?.GetValue<int>()??0;
        foreach(var change in effects.Fields())
        {
            if(change.Name is not ("affinity" or "trust" or "tension" or "familiarity"))continue;
            var before=Current(change.Name).Number();var delta=change.Value.Number();
            var positive=delta>=0;var limit=policy.Get(positive?"daily_up":"daily_down").Get(change.Name).Number();
            var ledger=positive?up:down;var used=ledger[change.Name]?.GetValue<double>()??0;
            var saturation=delta>=0?(100-before)/100:(change.Name=="affinity"?(before+100)/200:before/100);
            delta=Math.Sign(delta)*Math.Min(Math.Abs(delta)*Math.Max(0,saturation)/(1+count*policy.Get(positive?"habit_positive":"habit_negative").Number()),Math.Max(0,limit-used));
            ledger[change.Name]=used+Math.Abs(delta);
            writes[PathKey(pair+"."+change.Name)]=LifeFact(Math.Clamp(before+delta,change.Name=="affinity"?-100:0,100));
        }
        habit[kind]=count+1;writes[PathKey(pair+".day")]=LifeFact(day);writes[PathKey(pair+".up")]=LifeFact(up);
        writes[PathKey(pair+".down")]=LifeFact(down);writes[PathKey(pair+".habit")]=LifeFact(habit);
        LifeStage(pair,writes);
    }
    private void LifeStage(string pair,Dictionary<FieldKey,Fact> writes)
    {
        var policy=lifeDefinition.Get("relationship");
        double Result(string axis)=>writes.GetValueOrDefault(PathKey(pair+"."+axis))?.Value.Number()??LifeNumber(pair+"."+axis);
        var previous=LifeValue(pair+".stage").Text();var hysteresis=policy.Get("stage_hysteresis").Number();var stage="生疏";
        foreach(var threshold in policy.Get("stages").Items())
        {
            var margin=previous==threshold.Get("id").Text()?-hysteresis:0;
            if(Result("affinity")>=threshold.Get("affinity").Number()+margin&&Result("trust")>=threshold.Get("trust").Number()+margin)
            {stage=threshold.Get("id").Text();break;}
        }
        if(Result("tension")>=policy.Get("hostile_tension").Number()-(previous=="敌视"?hysteresis:0))stage="敌视";
        writes[PathKey(pair+".stage")]=LifeFact(stage);
    }
    private void AdvanceLifeSound()
    {
        var writes=new Dictionary<FieldKey,Fact>();var last=LifeNumber("life.last_sense");
        foreach(var actor in actors.Keys)
        {
            var noiseUntil=0.0;
            if(LifeWorking(actor)&&running.TryGetValue(actor,out var work)&&lifeDefinition.Get("actions").Get(work.Decision.Action.Declaration.Get("life").Get("action").Text()).Get("noise").Number()>0)
            {
                noiseUntil=work.DueAt/contentTimeUnit;
                var elapsed=Math.Max(0,Math.Min(ContentTime,noiseUntil)-Math.Max(last,work.WorkStartedAt!.Value/contentTimeUnit));
                if(elapsed>0)foreach(var listener in actors.Keys.Where(listener=>listener!=actor&&LifeNumber(listener+".zone")==LifeNumber(actor+".zone")))
                    Scheduler.ApplyNeedEffects(listener,JsonSerializer.SerializeToElement(new {calm=-elapsed*lifeDefinition.Get("response").Get("noise_calm_per_minute").Number()}),Clock.Now);
            }
            if(LifeNumber(actor+".noise_until")!=noiseUntil)writes[PathKey(actor+".noise_until")]=LifeFact(noiseUntil);
        }
        if(ContentTime!=last)writes[PathKey("life.last_sense")]=LifeFact(ContentTime);
        if(writes.Count>0)Rules.Changed(World.Apply(writes));
    }
    private bool EvaluateLife(Decision decision,Dictionary<FieldKey,Fact> writes,List<Observation> feedback,List<(string Actor,JsonElement Effects)> needEffects)
    {
        var meta=decision.Action.Declaration.Get("life");if(meta.ValueKind!=JsonValueKind.Object)return true;
        var action=meta.Get("action").Text();var actor=decision.Actor;
        if(action is not ("request" or "fulfil"))
        {
            var rule=lifeDefinition.Get("actions").Get(action);
            if((rule.Get("light").Flag()||rule.Get("needs_light").Flag())&&!LifeLit((int)LifeObject(meta.Get("obj").Text()).Get("zone").Number()))return false;
            if(action=="join_seat")return LifeValue("life.seating").Items().Any(plan=>plan.Get("status").Text()=="fulfilled"&&plan.Get("executions").Items().Any(value=>value.Number()==decision.Execution));
            return true;
        }
        var target=meta.Get("target").Text();var category=meta.Get("category").Text();
        if(LifeNumber(actor+".zone")!=LifeNumber(target+".zone"))return false;
        if(spatialAuthorityEnabled&&placements.TryGetValue(actor,out var from)&&placements.TryGetValue(target,out var to)&&
            Math.Pow(from.X-to.X,2)+Math.Pow(from.Z-to.Z,2)>Math.Pow(lifeDefinition.Get("response").Get("range_m").Number(),2))return false;
        var categoryRule=lifeDefinition.Get("social").Get("categories").Get(category);
        if(running.TryGetValue(target,out var targetWork)&&lifeDefinition.Get("actions").Get(targetWork.Decision.Action.Declaration.Get("life").Get("action").Text()).Get("pose").Text()=="lie")return false;
        var response=lifeDefinition.Get("response");var contracts=JsonNode.Parse(LifeValue("life.contracts").GetRawText())!.AsArray();
        var mode="accept";var responder=target;var requester=actor;var scores=new Dictionary<string,double>();
        if(action=="fulfil")
        {
            responder=actor;requester=target;
            var contract=LifeContract(responder,requester,category);
            if(contract is null||contract.Value.Get("status").Text()!="pending"||ContentTime<contract.Value.Get("due").Number()||ContentTime>=contract.Value.Get("expires").Number()||
                contract.Value.Get("mode").Text()=="conditional"&&Needs(responder).GetValueOrDefault("calm")<response.Get("calm_condition").Number()||!LifeCanDeliver(responder,requester,category))return false;
            contracts.OfType<JsonObject>().First(item=>item["id"]!.GetValue<string>()==contract.Value.Get("id").Text())["status"]="fulfilled";
        }
        else
        {
            scores=LifeReply(responder,requester,category,LifeBelievesCanDeliver(responder,requester,category));
            var maximum=scores.Values.Max();var weights=scores.ToDictionary(pair=>pair.Key,pair=>Math.Exp((pair.Value-maximum)/response.Get("temperature").Number()));
            var random=(uint)LifeNumber("life.rng");random=unchecked(random*1664525+1013904223);
            writes[PathKey("life.rng")]=LifeFact(random);var pick=random/(double)uint.MaxValue*weights.Values.Sum();
            foreach(var optionWeight in weights){mode=optionWeight.Key;pick-=optionWeight.Value;if(pick<=0)break;}
            if(mode is "conditional" or "defer")
                contracts.Add(LifeScenario.Object(new {id="promise/"+decision.Execution,actor=responder,target=requester,category,mode,status="pending",due=ContentTime+response.Get("delay_minutes").Number(),expires=ContentTime+response.Get("expiry_minutes").Number()}));
        }
        var accepted=mode is "accept" or "comply";
        if(accepted&&!LifeCanDeliver(responder,requester,category))return false;
        var effect=categoryRule.Get("fx").Text();
        var delivered=accepted&&effect is not ("hangout" or "yield_object");
        if(accepted&&!delivered)
        {
            var promise=action=="fulfil"?LifeContract(responder,requester,category):null;
            var linked=promise?.Get("id").Text()??"";
            if(linked.Length>0)contracts.OfType<JsonObject>().First(item=>item["id"]!.GetValue<string>()==linked)["status"]="awaiting_seating";
            var seating=JsonNode.Parse(LifeValue("life.seating").GetRawText())!.AsArray();
            seating.Add(LifeScenario.Object(new {id="seating/"+decision.Execution,requester,responder,category,effect,contract=linked,status="pending",participants=LifeSeats(responder,requester,effect),overlap=0.0,last=ContentTime,expires=promise?.Get("expires").Number()??ContentTime+response.Get("expiry_minutes").Number()}));
            writes[PathKey("life.seating")]=LifeFact(seating);
        }
        if(delivered)
        {
            if(effect is "share_food" or "offer_food")
            {
                var donor=effect=="share_food"?responder:requester;var recipient=effect=="share_food"?requester:responder;
                writes[PathKey(donor+".food")]=LifeFact(LifeNumber(donor+".food")-1);
                writes[PathKey(recipient+".food")]=LifeFact(LifeNumber(recipient+".food")+1);
                var repayment=Math.Min(1,LifeNumber(Pair(donor,recipient)+".owe"));
                writes[PathKey(Pair(donor,recipient)+".owe")]=LifeFact(LifeNumber(Pair(donor,recipient)+".owe")-repayment);
                writes[PathKey(Pair(recipient,donor)+".owe")]=LifeFact(LifeNumber(Pair(recipient,donor)+".owe")+1-repayment);
            }
            if(effect=="stop_noise")
            {
                writes[PathKey(responder+".noise_until")]=LifeFact(0);
                writes[PathKey(responder+".quiet_until")]=LifeFact(ContentTime+response.Get("cooldown_minutes").Number());
            }
            var gains=categoryRule.Get("need").Fields().Where(field=>field.Name!="hunger").ToDictionary(field=>field.Name,field=>field.Value.Number());
            foreach(var gain in lifeDefinition.Get("agents").Items().Single(profile=>profile.Get("id").Text()==requester).Get("social_motives").Get(category).Fields())gains[gain.Name]=gain.Value.Number();
            needEffects.Add((requester,JsonSerializer.SerializeToElement(gains)));
            if(effect is "talk" or "hangout")needEffects.Add((responder,JsonSerializer.SerializeToElement(gains)));
        }
        var modeRule=lifeDefinition.Get("social").Get("mode_effects").Get(mode);
        var weight=categoryRule.Get("weight").Number();
        foreach(var side in new[]{(From:requester,To:responder,Prefix:"q_"),(From:responder,To:requester,Prefix:"r_")})
        {
            var changes=modeRule.Fields().Where(field=>field.Name.StartsWith(side.Prefix,StringComparison.Ordinal)).ToDictionary(
                field=>field.Name[side.Prefix.Length..] switch {"aff"=>"affinity",var axis=>axis},field=>field.Value.Number()*weight);
            if(!delivered)changes.Remove("trust");
            LifeRelation(side.From,side.To,category,JsonSerializer.SerializeToElement(changes),writes);
        }
        writes[PathKey("life.contracts")]=LifeFact(contracts);
        var result=JsonSerializer.SerializeToElement(new {requester,responder,category,mode,accepted,delivered,scores,contract=action=="fulfil",effect});
        RecordMechanic(decision,"life_response",true,result);
        var message=JsonSerializer.SerializeToElement(new {requester,responder,category,mode,accepted,delivered,contract=action=="fulfil",effect,channel="communication"});
        foreach(var participant in new[]{requester,responder})
        {
            var key=PathKey(participant+".last_response");var observation=new Observation("life/"+(++nextEvidence),key,message,1,ContentTime,InformationOrigin.Communication,message);
            if(participant==actor)feedback.Add(observation);else actors[participant].ReceiveDirected(observation);
        }
        return true;
    }
    private void CommitLifeConsequences(Decision decision)
    {
        if(!IsLifeSession)return;
        var response=mechanicHistory.LastOrDefault(item=>item.Execution==decision.Execution&&item.Kind=="life_response");
        if(response is null||!response.Details.Get("accepted").Flag())return;
        var effect=response.Details.Get("effect").Text();
        var responder=response.Details.Get("responder").Text();
        if(effect is "hangout" or "yield_object")BeginLifeSeating(decision.Execution);
        if(effect is "yield_object" or "stop_noise"&&running.TryGetValue(responder,out var work)&&work.Decision.Execution!=decision.Execution)
        {
            if(effect=="yield_object"||lifeDefinition.Get("actions").Get(work.Decision.Action.Declaration.Get("life").Get("action").Text()).Get("noise").Number()>0)
                RequestCancel(responder);
        }
    }
    public object LifeAudit()=>new {
        supplied=LifeNumber("life.supplied"),consumed=LifeNumber("life.consumed"),
        stock=lifeDefinition.Get("objects").Items().Sum(item=>LifeNumber(item.Get("id").Text()+".stock")),
        carried=actors.Keys.Sum(actor=>LifeNumber(actor+".food")),
        contracts=LifeValue("life.contracts"),seating=LifeValue("life.seating"),
        cognition=actors.Values.Select(client=>new {actor=client.Id,revision=client.KnowledgeRevision,updating=client.IsUpdating,
            results=client.View().Knowledge.Where(item=>item.Key.Facet=="infer"&&item.Value.Known).Select(item=>new {key=item.Key,status=item.Value.Value}).ToArray()}).ToArray(),
        relations=actors.Keys.SelectMany(from=>actors.Keys.Where(to=>to!=from).Select(to=>new {from,to,affinity=LifeNumber(Pair(from,to)+".affinity"),trust=LifeNumber(Pair(from,to)+".trust"),tension=LifeNumber(Pair(from,to)+".tension"),stage=LifeValue(Pair(from,to)+".stage").Text()})).ToArray()
    };
}
