using System.Text.Json;

namespace DuelView.Runtime;

/// <summary>
/// Life-session reasoning. For each actor it derives, from that actor's own beliefs only, the
/// ordered steps that would satisfy a need which needs a resource chain (food: look, take,
/// eat, or ask someone; reading: fetch a book, sit in a lit free seat). The plan then
/// (a) forbids prerequisite work with no feasible downstream use, (b) rewards the first step of
/// a ready plan, and (c) rewards the information-gathering step when the plan is blocked only by
/// an unknown. It never reads the objective world: an unknown stays unknown until observed.
/// </summary>
public sealed partial class RuntimeSession
{
    public sealed record LifePlan(string Actor,string Need,string Status,string[] Steps,string Why,string[] Unknown);
    private readonly Dictionary<string,(double Minute,long Revision,LifePlan[] Plans)> lifePlanCache=new(StringComparer.Ordinal);

    private IEnumerable<JsonElement> LifeObjectsOf(string action)
    {
        var kinds=lifeDefinition.Get("actions").Get(action).Get("kinds").Items().Select(kind=>kind.Text()).ToHashSet(StringComparer.Ordinal);
        return lifeDefinition.Get("objects").Items().Where(item=>kinds.Contains(item.Get("kind").Text()));
    }
    // Same usability test as the live eligibility check, evaluated on the actor's own beliefs.
    private bool LifeUsable(string actor,string action,JsonElement item)
    {
        var definition=lifeDefinition.Get("actions").Get(action);var client=actors[actor];var zone=(int)item.Get("zone").Number();
        if((definition.Get("light").Flag()||definition.Get("needs_light").Flag())&&!LifeLitKnown(actor,zone))return false;
        if(client.Recall(PathKey(item.Get("id").Text()+".occupants")) is {Known:true} occupied&&
            occupied.Value.Items().Count(value=>value.Get("actor").Text()!=actor)>=(int)item.Get("capacity").Number(1))return false;
        var near=definition.Get("near").Items().Select(value=>value.Text()).ToArray();
        return near.Length==0||lifeDefinition.Get("objects").Items().Any(other=>near.Contains(other.Get("kind").Text())&&other.Get("zone").Number()==zone&&
            Math.Pow(other.Get("x").Number()-item.Get("x").Number(),2)+Math.Pow(other.Get("z").Number()-item.Get("z").Number(),2)<Math.Pow(definition.Get("near_dist").Number(),2));
    }
    private LifePlan[] LifePlans(string actor)
    {
        var client=actors[actor];var minute=Math.Floor(ContentTime);
        if(lifePlanCache.TryGetValue(actor,out var cached)&&cached.Minute==minute&&cached.Revision==client.KnowledgeRevision)return cached.Plans;
        var plans=new List<LifePlan>();var needs=Needs(actor);var limits=lifeDefinition.Get("reasoning").Get("plan_needs");
        if(needs.TryGetValue("hunger",out var hunger)&&hunger<limits.Get("hunger").Number(85))
        {
            var retry=lifeDefinition.Get("inventory").Get("inspect_retry_minutes").Number(60);
            var pantries=lifeDefinition.Get("objects").Items().Where(item=>item.Get("kind").Text()=="cabinet").ToArray();
            double? Stock(JsonElement item)=>client.Recall(PathKey(item.Get("id").Text()+".stock")) is {Known:true,Conflicted:false} fact?fact.Value.Number():null;
            double Seen(JsonElement item)=>client.Recall(PathKey(item.Get("id").Text()+".stock"))?.ObservedAt??0;
            var stocked=pantries.Where(item=>Stock(item)>=1).Select(item=>item.Get("id").Text()).ToArray();
            var unknown=pantries.Where(item=>Stock(item) is null||Stock(item)==0&&ContentTime-Seen(item)>=retry).Select(item=>item.Get("id").Text()).ToArray();
            var supplier=actors.Keys.FirstOrDefault(other=>other!=actor&&LifeProved(actor,other,"can_request_food"));
            if(LifeKnownNumber(actor,actor+".food")>=1)plans.Add(new(actor,"hunger","ready",["eat_meal"],"自己携带口粮，直接进食。",[]));
            else if(stocked.Length>0)plans.Add(new(actor,"hunger","ready",["prepare_meal","eat_meal"],"已知"+stocked[0]+"有存粮：先取餐再进食。",[]));
            else if(unknown.Length>0)plans.Add(new(actor,"hunger","needs_info",["inspect_pantry","prepare_meal","eat_meal"],"没有已知存粮，但"+unknown.Length+"个柜子库存未知或已过复查时间：先查看。",unknown));
            else if(supplier is not null)plans.Add(new(actor,"hunger","needs_social",["request:ask_share:"+supplier,"eat_meal"],"柜子都已知为空；推理认为"+supplier+"可请求口粮。",[]));
            else plans.Add(new(actor,"hunger","blocked",[],"已知柜子皆空且没有可请求的人：不再重复空跑，等待补给。",[]));
        }
        if(needs.TryGetValue("growth",out var growth)&&growth<limits.Get("growth").Number(92))
        {
            var holds=client.Recall(PathKey(actor+".book")) is {Known:true} book&&book.Value.Flag();
            var seat=LifeObjectsOf("read_seated").Any(item=>LifeUsable(actor,"read_seated",item));
            var shelf=LifeObjectsOf("read").Any();
            if(holds)plans.Add(seat?new(actor,"growth","ready",["read_seated"],"已持书且有可用的亮灯空位。",[]):new(actor,"growth","blocked",[],"已持书但没有可用的亮灯空位。",[]));
            else if(shelf&&seat)plans.Add(new(actor,"growth","ready",["read","read_seated"],"有书架且有可用的亮灯空位：先取书再就座。",[]));
            else plans.Add(new(actor,"growth","blocked",[],shelf?"没有可用的亮灯空位，取书只会白跑。":"没有书架。",[]));
        }
        var result=plans.ToArray();lifePlanCache[actor]=(minute,client.KnowledgeRevision,result);return result;
    }
    /// <summary>Reason a prerequisite action would be wasted work for this actor, or null.</summary>
    private string? LifeUselessReason(string actor,string kind)
    {
        if(kind is not ("read" or "return_book"))return null;
        var growth=LifePlans(actor).FirstOrDefault(plan=>plan.Need=="growth");
        if(kind=="read")return growth is null?"求知已满足，取书没有用途。":growth.Status=="blocked"?growth.Why:null;
        var hour=ContentTime%1440/60;var timing=lifeDefinition.Get("time");
        var night=hour>=timing.Get("night_from").Number()||hour<timing.Get("night_to").Number();
        return growth is {Status:"ready"}&&!night?"书还没读，先完成阅读计划。":null;
    }
    private static uint LifeHash(string text)
    {
        var hash=2166136261u;foreach(var character in text)hash=unchecked((hash^character)*16777619u);return hash;
    }
    private double LifePlanBias(string actor,ActionCandidate candidate)
    {
        if(!IsLifeSession||!actors.ContainsKey(actor))return 0;
        var meta=candidate.Declaration.Get("life");if(meta.ValueKind!=JsonValueKind.Object)return 0;
        var kind=meta.Get("action").Text();if(kind is "request" or "fulfil" or "join_seat")return 0;
        var config=lifeDefinition.Get("reasoning");var bias=0.0;var obj=meta.Get("obj").Text();
        foreach(var plan in LifePlans(actor))
        {
            var first=plan.Steps.FirstOrDefault()??"";
            if(plan.Status=="ready"&&(first==kind||first=="eat_meal"&&kind=="eat_standing"))bias+=config.Get("plan_bonus").Number();
            if(plan.Status=="needs_info"&&kind=="inspect_pantry"&&plan.Unknown.Contains(obj))bias+=config.Get("info_bonus").Number();
        }
        if(obj.Length>0)
        {
            bias+=(LifeHash(actor+"|"+obj)%1000/1000.0-0.5)*2*config.Get("tie_jitter").Number();
            var target=candidate.Declaration.Get("motor").Get("target").Items().Select(value=>value.Number()).ToArray();
            if(target.Length==3&&placements.TryGetValue(actor,out var from))
                bias-=Math.Sqrt(Math.Pow(from.X-target[0],2)+Math.Pow(from.Z-target[2],2))*config.Get("distance_per_m").Number();
        }
        return bias;
    }
    public object LifeReasoningAudit()=>actors.Keys.Select(actor=>new {actor,plans=LifePlans(actor)}).ToArray();
}
