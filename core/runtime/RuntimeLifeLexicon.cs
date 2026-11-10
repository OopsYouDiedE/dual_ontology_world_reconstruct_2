using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Runtime;

/// <summary>
/// Subjective word meaning. A term such as "借/分一点", "小声点" or "待会儿" is one shared word, but each
/// person carries a private sense for it (declared in the life DV). The world records only what
/// was done; each side keeps its own reading and builds its own expectation from it. A divergence
/// stays invisible until an expectation fails, and then only the disappointed side knows why.
/// </summary>
public sealed partial class RuntimeSession
{
    private JsonElement LifeTerm(string term)=>lifeDefinition.Get("lexicon").Get("terms").Get(term);
    private string LifeSense(string actor,string term)
    {
        var own=lifeDefinition.Get("lexicon").Get("agents").Get(actor).Get(term).Text();
        return own.Length>0?own:LifeTerm(term).Get("default").Text();
    }
    private double LifeSenseValue(string term,string sense,string dimension)=>LifeTerm(term).Get("senses").Get(sense).Get(dimension).Number();
    private IEnumerable<string> LifeTermsFor(string category,string mode)=>lifeDefinition.Get("lexicon").Get("terms").Fields()
        .Where(term=>term.Value.Get("uses").Get("categories").Items().Any(item=>item.Text()==category)||term.Value.Get("uses").Get("modes").Items().Any(item=>item.Text()==mode))
        .Select(term=>term.Name);
    private static string LifeDimension(JsonElement term)=>term.Get("senses").Fields().SelectMany(sense=>sense.Value.Fields()).Select(field=>field.Name).First(name=>name!="label");

    private void LifeSendBelief(string recipient,string actor,Observation observation,List<Observation> feedback)
    {
        if(recipient==actor)feedback.Add(observation);else actors[recipient].ReceiveDirected(observation);
    }
    /// <summary>Applies each participant's own reading of the words used in one exchange.</summary>
    private void LifeMeaning(Decision decision,string requester,string responder,string category,string mode,bool delivered,string effect,
        Dictionary<FieldKey,Fact> writes,JsonArray contracts,JsonArray expectations,JsonArray utterances,List<Observation> feedback)
    {
        var grace=lifeDefinition.Get("lexicon").Get("return_grace_minutes").Number(360);
        foreach(var term in LifeTermsFor(category,mode))
        {
            var rule=LifeTerm(term);var dimension=LifeDimension(rule);
            var requesterSense=LifeSense(requester,term);var responderSense=LifeSense(responder,term);
            if(term=="give_back")
            {
                if(!delivered||effect is not ("share_food" or "offer_food"))continue;
                var donor=effect=="share_food"?responder:requester;var recipient=donor==responder?requester:responder;
                var repayment=Math.Min(1,LifeNumber(Pair(donor,recipient)+".owe"));
                var donorRepay=LifeSenseValue(term,LifeSense(donor,term),"repay");var recipientRepay=LifeSenseValue(term,LifeSense(recipient,term),"repay");
                writes[PathKey(Pair(recipient,donor)+".owe")]=LifeFact(Math.Max(0,LifeNumber(Pair(recipient,donor)+".owe")+recipientRepay-repayment));
                if(repayment>0)
                    foreach(var side in new[]{(From:donor,To:recipient),(From:recipient,To:donor)})
                        LifeRelation(side.From,side.To,"reciprocated",lifeDefinition.Get("relationship").Get("reciprocity_effects"),writes);
                foreach(var open in expectations.OfType<JsonObject>().Where(item=>item["status"]!.GetValue<string>()=="open"&&item["kind"]!.GetValue<string>()=="return"&&
                    item["holder"]!.GetValue<string>()==recipient&&item["subject"]!.GetValue<string>()==donor))
                {open["status"]="met";open["closed_at"]=ContentTime;}
                if(repayment==0&&donorRepay>0)
                    expectations.Add(LifeScenario.Object(new {id="expect/"+decision.Execution+"/"+term,holder=donor,subject=recipient,kind="return",term,
                        created=ContentTime,until=ContentTime+grace,held=LifeSense(donor,term),meant=LifeSense(recipient,term),status="open"}));
            }
            else if(term=="quiet")
            {
                if(!delivered||effect!="stop_noise")continue;
                writes[PathKey(responder+".quiet_until")]=LifeFact(ContentTime+LifeSenseValue(term,responderSense,dimension));
                expectations.Add(LifeScenario.Object(new {id="expect/"+decision.Execution+"/"+term,holder=requester,subject=responder,kind="quiet",term,
                    created=ContentTime,until=ContentTime+LifeSenseValue(term,requesterSense,dimension),held=requesterSense,meant=responderSense,status="open"}));
            }
            else if(term=="later")
            {
                var contract=contracts.OfType<JsonObject>().LastOrDefault(item=>item["id"]!.GetValue<string>()=="promise/"+decision.Execution);
                if(contract is null)continue;
                contract["due"]=ContentTime+LifeSenseValue(term,responderSense,dimension);
                // Only a real difference in meaning creates an expectation that cannot be met; an ordinary late
                // promise is already priced by the contract's own expiry.
                if(LifeSenseValue(term,requesterSense,dimension)<LifeSenseValue(term,responderSense,dimension))
                expectations.Add(LifeScenario.Object(new {id="expect/"+decision.Execution+"/"+term,holder=requester,subject=responder,kind="fulfil",term,contract=contract["id"]!.GetValue<string>(),
                    created=ContentTime,until=ContentTime+LifeSenseValue(term,requesterSense,dimension),held=requesterSense,meant=responderSense,status="open"}));
            }
            var aligned=LifeSenseValue(term,requesterSense,dimension)==LifeSenseValue(term,responderSense,dimension);
            utterances.Add(LifeScenario.Object(new {time=ContentTime,term,word=rule.Get("word").Text(),category,mode,requester,responder,
                senses=new Dictionary<string,string>{[requester]=requesterSense,[responder]=responderSense},aligned}));
            foreach(var participant in new[]{requester,responder})
            {
                var own=participant==requester?requesterSense:responderSense;
                var other=participant==requester?responder:requester;
                var belief=JsonSerializer.SerializeToElement(new {term,word=rule.Get("word").Text(),sense=own,label=LifeTerm(term).Get("senses").Get(own).Get("label").Text(),with_actor=other,channel="own_reading"});
                LifeSendBelief(participant,decision.Actor,new("life/"+(++nextEvidence),PathKey(participant+".lexeme."+term),belief,1,ContentTime,InformationOrigin.Communication,belief),feedback);
            }
        }
        var limit=(int)lifeDefinition.Get("lexicon").Get("history_limit").Number(40);
        while(utterances.Count>limit)utterances.RemoveAt(0);
        while(expectations.Count>limit*2&&expectations.OfType<JsonObject>().Any(item=>item["status"]!.GetValue<string>()!="open"))
            expectations.Remove(expectations.OfType<JsonObject>().First(item=>item["status"]!.GetValue<string>()!="open"));
    }
    private JsonArray LifeArray(string path)=>LifeValue(path).ValueKind==JsonValueKind.Array?JsonNode.Parse(LifeValue(path).GetRawText())!.AsArray():new JsonArray();
    /// <summary>Closes expectations. A failed one hurts only the holder's view of the other person.</summary>
    private void AdvanceLifeExpectations()
    {
        if(LifeValue("life.expectations").ValueKind!=JsonValueKind.Array)return;
        var expectations=LifeArray("life.expectations");var contracts=LifeArray("life.contracts");var writes=new Dictionary<FieldKey,Fact>();var changed=false;
        var grievance=lifeDefinition.Get("lexicon").Get("grievance");
        foreach(var item in expectations.OfType<JsonObject>().Where(entry=>entry["status"]!.GetValue<string>()=="open"))
        {
            var holder=item["holder"]!.GetValue<string>();var subject=item["subject"]!.GetValue<string>();var kind=item["kind"]!.GetValue<string>();
            var until=item["until"]!.GetValue<double>();var outcome="";
            if(kind=="quiet")
            {
                if(ContentTime>item["created"]!.GetValue<double>()&&LifeNumber(subject+".noise_until")>ContentTime&&LifeNumber(subject+".zone")==LifeNumber(holder+".zone")&&ContentTime<until)outcome="violated";
                else if(ContentTime>=until)outcome="met";
            }
            else if(kind=="fulfil")
            {
                var status=contracts.OfType<JsonObject>().FirstOrDefault(contract=>contract["id"]!.GetValue<string>()==item["contract"]!.GetValue<string>())?["status"]?.GetValue<string>()??"missing";
                if(status=="fulfilled")outcome="met";
                else if(status is "expired" or "missing")outcome="lapsed";
                else if(ContentTime>=until)outcome="violated";
            }
            else if(kind=="return"&&ContentTime>=until)outcome="violated";
            if(outcome.Length==0)continue;
            item["status"]=outcome;item["closed_at"]=ContentTime;changed=true;
            if(outcome!="violated")continue;
            LifeRelation(holder,subject,"grievance",JsonSerializer.SerializeToElement(new {tension=grievance.Get("tension").Number(),trust=grievance.Get("trust").Number()}),writes);
            Scheduler.ApplyNeedEffects(holder,JsonSerializer.SerializeToElement(new {calm=grievance.Get("calm").Number()}),Clock.Now);
            var detail=JsonSerializer.SerializeToElement(new {holder,subject,kind,term=item["term"]!.GetValue<string>(),holder_reading=item["held"]!.GetValue<string>(),other_reading=item["meant"]!.GetValue<string>()});
            mechanicHistory.Add(new(ContentTime,0,"world",item["id"]!.GetValue<string>(),"life_expectation",false,detail));
            actors[holder].ReceiveSalient(new("life/"+(++nextEvidence),PathKey(holder+".last_grievance"),
                JsonSerializer.SerializeToElement(new {with_actor=subject,kind,term=item["term"]!.GetValue<string>(),expected_reading=item["held"]!.GetValue<string>()}),1,ContentTime,InformationOrigin.Passive,detail));
        }
        if(!changed)return;
        writes[PathKey("life.expectations")]=LifeFact(expectations);
        Rules.Changed(World.Apply(writes));
    }
    public object LifeLexiconAudit()=>new {
        senses=actors.Keys.ToDictionary(actor=>actor,actor=>lifeDefinition.Get("lexicon").Get("terms").Fields().ToDictionary(term=>term.Name,term=>LifeSense(actor,term.Name))),
        utterances=LifeValue("life.utterances"),expectations=LifeValue("life.expectations")};
}
