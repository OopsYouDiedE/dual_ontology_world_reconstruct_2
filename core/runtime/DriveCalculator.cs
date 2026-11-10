using System.Text.Json;

namespace DuelView.Runtime;

public sealed record NeedCheckpoint(string Id,double Value,double Time);
public sealed record BuffCheckpoint(string Id,double Started,double Duration,string Source);
public sealed record AffectEvent(string Kind,string Label,double Time,double Duration,string Source);
public sealed record DriveState(NeedCheckpoint[] Needs,BuffCheckpoint[]? Buffs=null,string? Emotion=null,AffectEvent[]? Events=null);

/// <summary>Analytic decay and single-action utility. No search tree or per-frame
/// need writes are needed. All traits, rates and action effects originate in DV.</summary>
public sealed class DriveCalculator
{
    // The authored need vocabulary is deliberately bounded so candidate selection
    // and scoring have a fixed upper cost independent of content catalog size.
    private const int MaximumNeeds = 32;
    private sealed record Need(double Value, double Time, double Decay, double Weight);
    private readonly Dictionary<string, Need> needs = new(StringComparer.Ordinal);
    private JsonElement declaration;
    private readonly Dictionary<string,BuffCheckpoint> buffs=new(StringComparer.Ordinal);
    private readonly Queue<AffectEvent> events=new();
    private string emotion="";
    public string Emotion=>emotion;
    public IReadOnlyCollection<BuffCheckpoint> Buffs=>buffs.Values;
    public IEnumerable<AffectEvent> DrainEvents(){while(events.TryDequeue(out var item))yield return item;}
    public bool Tick(double now)
    {
        ValidateTime(now);
        var changed=false;
        foreach(var buff in buffs.Values.Where(b=>b.Duration>0&&b.Started+b.Duration<=now).OrderBy(b=>b.Started+b.Duration).ToArray())
        {
            buffs.Remove(buff.Id);
            changed=true;
            events.Enqueue(new("buff_expired","[Buff过期] "+BuffDefinition(buff.Id).Get("label").Text(buff.Id),buff.Started+buff.Duration,0,buff.Source));
        }
        if(changed)
        {
            var dom=CalculateDominantBuffEmotion(now);
            if(dom.Length>0&&dom!=emotion)
            {
                events.Enqueue(new("emotion_changed","[情绪切换] "+emotion+" → "+dom,now,0,"buff_expired"));
                emotion=dom;
            }
        }
        return changed;
    }
    private string CalculateDominantBuffEmotion(double now)
    {
        var scores=new Dictionary<string,double>(StringComparer.Ordinal);
        foreach(var buff in buffs.Values.Where(b=>b.Started<=now&&(b.Duration==0||now<b.Started+b.Duration)))
        {
            var def=BuffDefinition(buff.Id);
            var emo=def.Get("emotion").Text();
            if(emo.Length>0)
            {
                var weight=def.Get("emotion_weight").Number(1);
                scores[emo]=scores.GetValueOrDefault(emo)+weight;
            }
        }
        return scores.Count>0?scores.OrderByDescending(p=>p.Value).First().Key:"";
    }
    private JsonElement BuffDefinition(string id)=>declaration.Get("buff_definitions").Get(id);

    public DriveCalculator(JsonElement declaration, double now) => Reconfigure(declaration, now);

    public void Reconfigure(JsonElement policy, double now)
    {
        ValidateTime(now);
        var configured=new Dictionary<string,Need>(StringComparer.Ordinal);
        foreach (var item in policy.Get("commodity_needs").Fields())
        {
            if (configured.Count >= MaximumNeeds)
                throw new InvalidDataException("Daily need vocabulary exceeds the fixed runtime budget.");
            var value = item.Value.Number(double.NaN);
            var decay = policy.Get("need_decay_per_second").Get(item.Name).Number();
            var weight = policy.Get("autonomy_weights").Get(item.Name).Number();
            if (!double.IsFinite(value) || value is < 0 or > 100 || !double.IsFinite(decay) || decay < 0 || !double.IsFinite(weight) || weight < 0)
                throw new InvalidDataException("Invalid DV daily need: " + item.Name);
            configured.Add(item.Name,new(needs.TryGetValue(item.Name,out var existing)?At(existing,now):value,now,decay,weight));
        }
        foreach (var group in new[] { "action_predictions", "completed_action_effects" })
            foreach (var action in policy.Get(group).Fields())
                foreach (var effect in action.Value.Fields())
                    if (!configured.ContainsKey(effect.Name) || !double.IsFinite(effect.Value.Number(double.NaN)))
                        throw new InvalidDataException("Invalid authored need effect: " + effect.Name);
        foreach(var state in policy.Get("emotion_definitions").Fields())
            foreach(var score in state.Value.Get("tag_scores").Fields())
                if(!double.IsFinite(score.Value.Number(double.NaN)))throw new InvalidDataException("Invalid emotion utility: "+state.Name);
        declaration=policy.Clone();
        if(emotion.Length==0)emotion=policy.Get("initial_emotion").Text();
        needs.Clear();
        foreach(var pair in configured) needs.Add(pair.Key,pair.Value);
    }

    private static double At(Need need, double now) => Math.Clamp(need.Value - Math.Max(0, now - need.Time) * need.Decay, 0, 100);

    private JsonElement Effects(ActionCandidate action,string direct,string group)
    {
        var value=action.Declaration.Get(direct);
        if(value.ValueKind==JsonValueKind.Object) return value;
        value=declaration.Get(group).Get(action.Id);
        return value.ValueKind==JsonValueKind.Object?value:declaration.Get(group).Get(action.Declaration.Get("kind").Text());
    }

    public IReadOnlyDictionary<string,double> Snapshot(double now)
    {
        ValidateTime(now);
        return needs.ToDictionary(pair=>pair.Key,pair=>At(pair.Value,now),StringComparer.Ordinal);
    }
    public DriveState SaveState()=>new(needs.Select(pair=>new NeedCheckpoint(pair.Key,pair.Value.Value,pair.Value.Time)).ToArray(),buffs.Values.ToArray(),emotion,events.ToArray());
    public void RestoreState(DriveState state)
    {
        if(state.Needs is null || state.Needs.Length!=needs.Count || state.Needs.Select(item=>item.Id).Distinct(StringComparer.Ordinal).Count()!=needs.Count)
            throw new InvalidDataException("Incompatible need checkpoint.");
        foreach(var item in state.Needs)
            if(!needs.ContainsKey(item.Id)||!double.IsFinite(item.Value)||item.Value is <0 or >100||!double.IsFinite(item.Time)||item.Time<0)
                throw new InvalidDataException("Invalid need checkpoint.");
        foreach(var item in state.Needs)needs[item.Id]=needs[item.Id] with {Value=item.Value,Time=item.Time};
        buffs.Clear();
        foreach(var buff in state.Buffs??[])
        {
            if(BuffDefinition(buff.Id).ValueKind!=JsonValueKind.Object||!double.IsFinite(buff.Started)||buff.Started<0||!double.IsFinite(buff.Duration)||buff.Duration<0)
                throw new InvalidDataException("Invalid buff checkpoint.");
            buffs.Add(buff.Id,buff);
        }
        emotion=state.Emotion??emotion;events.Clear();foreach(var item in state.Events??[])events.Enqueue(item);
    }

    internal IEnumerable<string> AffectedDrives(ActionCandidate action) =>
        Effects(action,"perceived_need_effects","action_predictions").Fields()
            .Where(effect=>effect.Value.Number()>0).Select(effect=>effect.Name)
            .Concat(ActionWeight(action).Get("scale").Number()>0?[ActionWeight(action).Get("need").Text()]:[])
            .Where(name=>name.Length>0).Distinct(StringComparer.Ordinal);
    internal double CompletedEffect(ActionCandidate action,string need)=>Effects(action,"completed_need_effects","completed_action_effects").Get(need).Number();

    internal void Validate(ActionCandidate action)
    {
        foreach(var id in action.Declaration.Get("add_buffs").Items())
        {
            var definition=BuffDefinition(id.Text());var duration=definition.Get("until_resolved").Flag()?0:definition.Get("duration_minutes").Number(double.NaN);
            if(!double.IsFinite(duration)||duration<0||duration==0&&!definition.Get("until_resolved").Flag()||definition.Get("label").Text().Length==0)
                throw new InvalidDataException("Invalid authored buff: "+id.Text());
            foreach(var bonus in definition.Get("tag_scores").Fields())if(!double.IsFinite(bonus.Value.Number(double.NaN)))throw new InvalidDataException("Invalid buff utility.");
            foreach(var multiplier in definition.Get("need_effect_multipliers").Fields())
                if(!needs.ContainsKey(multiplier.Name)||!double.IsFinite(multiplier.Value.Number(double.NaN))||multiplier.Value.Number()<0)
                    throw new InvalidDataException("Invalid buff need multiplier.");
        }
        foreach(var effect in Effects(action,"perceived_need_effects","action_predictions").Fields()
            .Concat(Effects(action,"completed_need_effects","completed_action_effects").Fields()))
            if(!needs.ContainsKey(effect.Name)||!double.IsFinite(effect.Value.Number(double.NaN)))
                throw new InvalidDataException("Invalid action need effect: "+effect.Name);
    }

    private JsonElement ActionWeight(ActionCandidate action)
    {
        var weight=declaration.Get("action_weights").Get(action.Id);
        return weight.ValueKind==JsonValueKind.Object?weight:declaration.Get("action_weights").Get(action.Declaration.Get("kind").Text());
    }

    internal IEnumerable<string> Priorities(double now) => needs
        .OrderByDescending(pair=>(100-At(pair.Value,now))*pair.Value.Weight).Select(pair=>pair.Key);

    public double Score(ActionCandidate action,double now) => Calculate(action,now,null);

    public DriveEvaluation Evaluate(ActionCandidate action,double now)
    {
        var contributions=new Dictionary<string,double>(StringComparer.Ordinal);
        var score=Calculate(action,now,contributions);
        return new(action.Id,score,contributions,action.Duration*declaration.Get("time_cost").Number(),action.Score*declaration.Get("score_scale").Number(1));
    }

    private double Calculate(ActionCandidate action, double now, Dictionary<string,double>? contributions)
    {
        ValidateTime(now);
        var score = action.Score;
        var emotionUtility=action.Declaration.Get("tags").Items().Select(tag=>tag.Text()).Distinct(StringComparer.Ordinal)
            .Sum(tag=>declaration.Get("emotion_definitions").Get(emotion).Get("tag_scores").Get(tag).Number());
        score+=emotionUtility;
        if(contributions is not null&&emotion.Length>0)contributions["emotion:"+emotion]=emotionUtility;
        foreach(var buff in buffs.Values.Where(b=>b.Started<=now&&(b.Duration==0||now<b.Started+b.Duration)))
        {
            var utility=action.Declaration.Get("tags").Items().Select(tag=>tag.Text()).Distinct(StringComparer.Ordinal)
                .Sum(tag=>BuffDefinition(buff.Id).Get("tag_scores").Get(tag).Number());
            score+=utility;
            if(contributions is not null)contributions["buff:"+buff.Id]=utility;
        }
        foreach (var prediction in Effects(action,"perceived_need_effects","action_predictions").Fields())
        {
            if (!needs.TryGetValue(prediction.Name, out var need)) throw new InvalidDataException("Undeclared predicted need.");
            var value = At(need, now);
            var improvement = Math.Clamp(value + AdjustEffect(prediction.Name,prediction.Value.Number(),now), 0, 100) - value;
            var utility=improvement*need.Weight*(100-value)/100;
            score += utility;
            if(contributions is not null) contributions[prediction.Name]=utility;
        }
        var weight = ActionWeight(action);
        if (needs.TryGetValue(weight.Get("need").Text(), out var weighted))
        {
            var utility=(100-At(weighted,now))*weight.Get("scale").Number();
            score+=utility;
            if(contributions is not null) contributions[weight.Get("need").Text()]=contributions.GetValueOrDefault(weight.Get("need").Text())+utility;
        }
        var scale=declaration.Get("score_scale").Number(1);
        score *= scale;
        if(contributions is not null)foreach(var key in contributions.Keys.ToArray())contributions[key]*=scale;
        score -= action.Duration * declaration.Get("time_cost").Number();
        if (!double.IsFinite(score)) throw new InvalidDataException("Daily action score is not finite.");
        return score;
    }

    internal void Complete(ActionCandidate action, double now)
    {
        ValidateTime(now);
        Tick(now);
        foreach(var id in action.Declaration.Get("remove_buffs").Items())
            if(buffs.Remove(id.Text(),out var removed))events.Enqueue(new("buff_removed","[Buff移除] "+BuffDefinition(removed.Id).Get("label").Text(removed.Id),now,0,action.Id));
        foreach(var id in action.Declaration.Get("add_buffs").Items())
        {
            var definition=BuffDefinition(id.Text());var duration=definition.Get("until_resolved").Flag()?0:definition.Get("duration_minutes").Number()*60;
            var refresh=buffs.ContainsKey(id.Text());buffs[id.Text()]=new(id.Text(),now,duration,action.Id);
            var effects=string.Join("、",definition.Get("tag_scores").Fields().Select(p=>EffectName(p.Name)+p.Value.Number().ToString("+0.##;-0.##;0",System.Globalization.CultureInfo.InvariantCulture))
                .Concat(definition.Get("need_effect_multipliers").Fields().Select(p=>EffectName(p.Name)+"恢复×"+p.Value.Number().ToString(System.Globalization.CultureInfo.InvariantCulture))));
            events.Enqueue(new(refresh?"buff_refreshed":"buff_added",(refresh?"[Buff刷新] ":"[Buff添加] ")+definition.Get("label").Text()+"｜"+effects+"｜"+(duration==0?"至"+definition.Get("resolution").Text():definition.Get("duration_minutes").Number().ToString(System.Globalization.CultureInfo.InvariantCulture)+"分钟"),now,0,action.Id));
        }
        var next=action.Declaration.Get("emotion").Text();
        var dominantBuffEmotion=CalculateDominantBuffEmotion(now);
        if(next.Length>0)
        {
            if(next!=emotion)
            {
                events.Enqueue(new("emotion_changed","[情绪切换] "+emotion+" → "+next,now,0,action.Id));emotion=next;
            }
        }
        else if(dominantBuffEmotion.Length>0&&dominantBuffEmotion!=emotion)
        {
            events.Enqueue(new("emotion_changed","[情绪切换] "+emotion+" → "+dominantBuffEmotion,now,0,action.Id));emotion=dominantBuffEmotion;
        }
        foreach (var effect in Effects(action,"completed_need_effects","completed_action_effects").Fields())
        {
            if (!needs.TryGetValue(effect.Name, out var before)) throw new InvalidDataException("Undeclared completion need.");
            needs[effect.Name] = before with { Value = Math.Clamp(At(before, now) + AdjustEffect(effect.Name,effect.Value.Number(),now), 0, 100), Time = now };
        }
    }

    private static string EffectName(string id)=>id switch
    {
        "self_care"=>"自护倾向", "daily"=>"日常倾向", "new_room"=>"探索倾向",
        "own_room"=>"室内查看倾向", "preserve"=>"保全倾向", "energy"=>"精力", "seek_help"=>"求助倾向", "care"=>"照护倾向", "social"=>"社交倾向", _=>id
    };

    private double AdjustEffect(string need,double value,double now)
    {
        foreach(var buff in buffs.Values.Where(b=>b.Started<=now&&(b.Duration==0||now<b.Started+b.Duration)))
            value*=BuffDefinition(buff.Id).Get("need_effect_multipliers").Get(need).Number(1);
        return value;
    }

    private static void ValidateTime(double now)
    {
        if(!double.IsFinite(now)||now<0)throw new ArgumentOutOfRangeException(nameof(now));
    }
}

public sealed record DriveEvaluation(string Action,double Score,IReadOnlyDictionary<string,double> NeedContributions,double TimeCost,double BaseBias);
