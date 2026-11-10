using System.Text.Json;

namespace DuelView.Runtime;

public sealed partial class RuntimeSession
{
    private void LifeFragment(string actor,string path,object value,string channel)
    {
        var key=PathKey(path);var encoded=JsonSerializer.SerializeToElement(value);var client=actors[actor];
        client.ReceiveFragment(new("life/fragment/"+actor+"/"+key+"/"+encoded.GetRawText()+"/"+ContentTime.ToString("R",System.Globalization.CultureInfo.InvariantCulture),key,encoded,1,ContentTime,InformationOrigin.Passive,
            JsonSerializer.SerializeToElement(new {actor,channel,fragment=key,observed_at=ContentTime})));
    }
    private void SenseLife(string actor)
    {
        var senses=lifeDefinition.Get("senses");var zone=LifeNumber(actor+".zone");
        foreach(var field in senses.Get("own_fields").Items())LifeObserve(actor,PathKey(actor+"."+field.Text()));
        var lit=LifeLit((int)zone);
        if(lit)foreach(var item in lifeDefinition.Get("objects").Items().Where(item=>item.Get("zone").Number()==zone))
            foreach(var field in senses.Get("object_fields").Items())LifeObserve(actor,PathKey(item.Get("id").Text()+"."+field.Text()));
        var audible=actors.Keys.Any(source=>LifeNumber(source+".zone")==zone&&LifeWorking(source)&&
            running.TryGetValue(source,out var work)&&lifeDefinition.Get("actions").Get(work.Decision.Action.Declaration.Get("life").Get("action").Text()).Get("noise").Number()>senses.Get("noise_threshold").Number());
        LifeFragment(actor,actor+".trace.music_audible",audible,"hearing");
        foreach(var other in actors.Keys.Where(other=>other!=actor))
        {
            foreach(var field in senses.Get("own_relation_fields").Items())LifeObserve(actor,PathKey(Pair(actor,other)+"."+field.Text()));
            var visible=lit&&LifeNumber(other+".zone")==zone;
            if(visible&&spatialAuthorityEnabled&&placements.TryGetValue(actor,out var from)&&placements.TryGetValue(other,out var to))
                visible=Math.Pow(from.X-to.X,2)+Math.Pow(from.Z-to.Z,2)<=Math.Pow(senses.Get("visual_range_m").Number(),2);
            LifeFragment(actor,other+".trace.in_view",visible,"visual_attention");
            if(!visible)continue;
            foreach(var field in senses.Get("target_fields").Items())LifeObserve(actor,PathKey(other+"."+field.Text()));
            foreach(var fragment in senses.Get("target_fragments").Items())
            {
                var value=fragment.Get("kind").Text() switch
                {
                    "positive"=>LifeNumber(other+"."+fragment.Get("source").Text())>0,
                    "working_action"=>LifeWorking(other)&&running.TryGetValue(other,out var work)&&work.Decision.Action.Declaration.Get("life").Get("action").Text()==fragment.Get("action").Text(),
                    _=>throw new InvalidDataException("未知生活感知片段。")
                };
                LifeFragment(actor,other+".trace."+fragment.Get("field").Text(),value,"vision");
            }
        }
    }
    private bool LifeProved(string actor,string target,string field)=>actors[actor].Recall(new(target,"infer",field)) is {Known:true,Conflicted:false} fact&&fact.Value.Text()=="proved";
    private double LifeKnownNumber(string actor,string path)=>actors[actor].Recall(PathKey(path)) is {Known:true,Conflicted:false} fact?fact.Value.Number():0;
    private bool LifeBelievesCanDeliver(string actor,string target,string category)
    {
        var effect=lifeDefinition.Get("social").Get("categories").Get(category).Get("fx").Text();
        if(effect=="share_food")return LifeKnownNumber(actor,actor+".food")>=1;
        if(effect=="offer_food")return LifeKnownNumber(actor,actor+".food")==0&&LifeProved(actor,target,"can_request_food");
        if(effect=="stop_noise")return LifeWorking(actor)&&running.TryGetValue(actor,out var work)&&
            lifeDefinition.Get("actions").Get(work.Decision.Action.Declaration.Get("life").Get("action").Text()).Get("noise").Number()>0;
        if(effect=="yield_object")return LifeWorking(actor)&&running.TryGetValue(actor,out var seated)&&
            lifeDefinition.Get("actions").Get(seated.Decision.Action.Declaration.Get("life").Get("action").Text()).Get("pose").Text()=="sit";
        return true;
    }
    public object CognitionAudit(string actor,bool includeProofs=false)
    {
        var client=actors[actor];
        var queries=client.Declaration.Get("cognition").Get("queries").Items();
        return new {actor,knowledge_revision=client.KnowledgeRevision,updating=client.IsUpdating,
            fragments=client.View().Knowledge.Where(item=>item.Key.Facet=="trace"&&item.Value.Known).Select(item=>new {key=item.Key,fact=item.Value}).ToArray(),
            queries=queries.Select(query=>
            {
                var key=FieldKey.Read(query.Get("ref"),actor);var fact=client.Recall(key);
                var proof=includeProofs?client.Evidence.LastOrDefault(item=>item.Key==key&&item.Method=="inference"):null;
                return new {id=query.Get("id").Text(),label=query.Get("label").Text(),key,status=fact?.Value.Text("pending")??"pending",confidence=fact?.Confidence,source=proof?.Source};
            }).ToArray()};
    }
}
