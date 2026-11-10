using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Runtime;

public sealed partial class RuntimeSession
{
    private static string LifeSeat(JsonElement participant)=>"life.slot."+participant.Get("obj").Text()+"."+(int)participant.Get("slot").Number();
    private JsonElement? LifeSeatingFor(string actor)=>LifeValue("life.seating").Items().Cast<JsonElement?>().FirstOrDefault(plan=>
        plan!.Value.Get("status").Text()=="pending"&&plan.Value.Get("expires").Number()>ContentTime&&
        plan.Value.Get("participants").Items().Any(participant=>participant.Get("actor").Text()==actor));
    private object[] LifeSeats(string responder,string requester,string effect)
    {
        if(LifeSeatingFor(responder) is not null||LifeSeatingFor(requester) is not null)return [];
        if(effect=="yield_object")
        {
            if(!running.TryGetValue(responder,out var work)||!LifeWorking(responder))return [];
            var meta=work.Decision.Action.Declaration.Get("life");
            if(lifeDefinition.Get("actions").Get(meta.Get("action").Text()).Get("pose").Text()!="sit")return [];
            return [new {actor=requester,obj=meta.Get("obj").Text(),slot=(int)meta.Get("slot").Number()}];
        }
        var distance=lifeDefinition.Get("response").Get("seat_range_m").Number();
        var seats=lifeDefinition.Get("objects").Items().Where(item=>item.Get("zone").Number()==LifeNumber(requester+".zone")&&
            lifeDefinition.Get("actions").Get("join_seat").Get("kinds").Items().Any(kind=>kind.Text()==item.Get("kind").Text()))
            .SelectMany(item=>Enumerable.Range(0,(int)item.Get("capacity").Number()).Select(slot=>(Item:item,Slot:slot))).ToArray();
        foreach(var first in seats)foreach(var second in seats)
        {
            var firstId=first.Item.Get("id").Text();var secondId=second.Item.Get("id").Text();
            if(firstId==secondId&&first.Slot==second.Slot)continue;
            if(Math.Pow(first.Item.Get("x").Number()-second.Item.Get("x").Number(),2)+Math.Pow(first.Item.Get("z").Number()-second.Item.Get("z").Number(),2)>distance*distance)continue;
            if(!Reservations.CanAcquire(requester,["life.slot."+firstId+"."+first.Slot])||!Reservations.CanAcquire(responder,["life.slot."+secondId+"."+second.Slot]))continue;
            return [new {actor=requester,obj=firstId,slot=first.Slot},new {actor=responder,obj=secondId,slot=second.Slot}];
        }
        return [];
    }
    private void BeginLifeSeating(long execution)
    {
        var plan=LifeValue("life.seating").Items().First(item=>item.Get("id").Text()=="seating/"+execution);
        foreach(var participant in plan.Get("participants").Items())
        {
            var actor=participant.Get("actor").Text();var resource=LifeSeat(participant);
            var reserved=plan.Get("effect").Text()=="yield_object"
                ?Reservations.Handoff(plan.Get("responder").Text(),new(actor,0),resource):Reservations.TryAcquire(new(actor,0),[resource]);
            if(!reserved)throw new InvalidOperationException("Accepted seating lost its checked reservation.");
            Rules.Changed(World.Apply(new Dictionary<FieldKey,Fact>{{PathKey(actor+".seat_plan"),LifeFact(plan.Get("id").Text())}}));
            LifeObserve(actor,PathKey(actor+".seat_plan"));
            if(running.TryGetValue(actor,out var work)&&work.Decision.Execution!=execution)RequestCancel(actor);
        }
    }
    private void AdvanceLifeSeating()
    {
        var plans=JsonNode.Parse(LifeValue("life.seating").GetRawText())!.AsArray();var writes=new Dictionary<FieldKey,Fact>();var changed=false;
        var contracts=JsonNode.Parse(LifeValue("life.contracts").GetRawText())!.AsArray();var contractsChanged=false;
        foreach(var plan in plans.OfType<JsonObject>().Where(plan=>plan["status"]!.GetValue<string>()=="pending"))
        {
            var data=JsonSerializer.SerializeToElement(plan);var participants=data.Get("participants").Items().ToArray();
            var elapsed=Math.Max(0,ContentTime-data.Get("last").Number());
            var together=participants.All(participant=>running.TryGetValue(participant.Get("actor").Text(),out var work)&&LifeWorking(participant.Get("actor").Text())&&
                work.Decision.Action.Declaration.Get("life").Get("action").Text()=="join_seat"&&work.Decision.Action.Declaration.Get("life").Get("obj").Text()==participant.Get("obj").Text()&&
                work.Decision.Action.Declaration.Get("life").Get("slot").Number()==participant.Get("slot").Number());
            if(together)elapsed=Math.Max(0,ContentTime-Math.Max(data.Get("last").Number(),participants.Max(participant=>running[participant.Get("actor").Text()].WorkStartedAt!.Value/contentTimeUnit)));
            if(together&&participants.Length>1&&spatialAuthorityEnabled)
            {
                var first=Placement(participants[0].Get("actor").Text());var second=Placement(participants[1].Get("actor").Text());
                together=first is not null&&second is not null&&Math.Pow(first.X-second.X,2)+Math.Pow(first.Z-second.Z,2)<=Math.Pow(lifeDefinition.Get("response").Get("seat_range_m").Number(),2);
            }
            plan["last"]=ContentTime;plan["overlap"]=together?data.Get("overlap").Number()+elapsed:0;changed|=elapsed>0;
            var fulfilled=plan["overlap"]!.GetValue<double>()>=lifeDefinition.Get("response").Get("seat_overlap_minutes").Number();
            if(!fulfilled&&ContentTime<data.Get("expires").Number())continue;
            plan["status"]=fulfilled?"fulfilled":"expired";changed=true;
            var linked=contracts.OfType<JsonObject>().FirstOrDefault(contract=>contract["id"]!.GetValue<string>()==data.Get("contract").Text());
            if(linked is not null)
            {
                linked["status"]=fulfilled?"fulfilled":"expired";contractsChanged=true;
            }
            foreach(var participant in participants)
            {
                var actor=participant.Get("actor").Text();Reservations.Release(new(actor,0));writes[PathKey(actor+".seat_plan")]=LifeFact("");
            }
            if(fulfilled)
            {
                plan["executions"]=JsonSerializer.SerializeToNode(participants.Select(participant=>running[participant.Get("actor").Text()].Decision.Execution).ToArray());
                var category=data.Get("category").Text();var gains=lifeDefinition.Get("social").Get("categories").Get(category).Get("need");
                foreach(var participant in participants)Scheduler.ApplyNeedEffects(participant.Get("actor").Text(),gains,Clock.Now);
                foreach(var side in new[]{(From:data.Get("requester").Text(),To:data.Get("responder").Text()),(From:data.Get("responder").Text(),To:data.Get("requester").Text())})
                    LifeRelation(side.From,side.To,"seating",lifeDefinition.Get("relationship").Get("fulfilled_effects"),writes);
            }
            mechanicHistory.Add(new(ContentTime,0,data.Get("requester").Text(),data.Get("id").Text(),"life_seating",fulfilled,JsonSerializer.SerializeToElement(plan)));
        }
        if(changed)writes[PathKey("life.seating")]=LifeFact(plans);
        if(contractsChanged)writes[PathKey("life.contracts")]=LifeFact(contracts);
        var leases=Reservations.SaveState();
        foreach(var item in lifeDefinition.Get("objects").Items())
        {
            var id=item.Get("id").Text();
            var occupants=JsonSerializer.SerializeToElement(Enumerable.Range(0,(int)item.Get("capacity").Number()).SelectMany(slot=>leases.Where(lease=>lease.Resources.Contains("life.slot."+id+"."+slot))
                .Select(lease=>new {slot,actor=lease.Owner.Actor})).Distinct().ToArray());
            if(!Values.Same(LifeValue(id+".occupants"),occupants))writes[PathKey(id+".occupants")]=LifeFact(occupants);
        }
        if(writes.Count>0)Rules.Changed(World.Apply(writes));
    }
}
