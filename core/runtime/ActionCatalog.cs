using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Runtime;

/// <summary>Compiles authored actor actions and their owned prediction laws once.
/// Objective enforcement is resolved separately from the physical world's adoptions.</summary>
public static class ActionCatalog
{
    public static IReadOnlyList<ActionCandidate> Compile(JsonElement actor, JsonElement world, JsonElement costs, JsonElement timing)
    {
        var subject = actor.Get("id").Text();
        var unit = timing.Get("content_time_unit_seconds").Number(double.NaN);
        var minimum = timing.Get("minimum_action_seconds").Number(double.NaN);
        if (!double.IsFinite(unit) || unit <= 0 || !double.IsFinite(minimum) || minimum <= 0) throw new InvalidDataException("Invalid authored action timing policy.");
        var result = new List<ActionCandidate>();
        foreach (var action in actor.Get("actions").Items())
        {
            var id = action.Get("id").Text();
            var kind = action.Get("kind").Text();
            var motor=action.Get("motor");
            if(action.Get("not_before_game_minutes").ValueKind!=JsonValueKind.Undefined &&
               (!double.IsFinite(action.Get("not_before_game_minutes").Number(double.NaN)) || action.Get("not_before_game_minutes").Number()<0))
                throw new InvalidDataException("Invalid authored action start time: "+id);
            if(action.Get("not_after_game_minutes").ValueKind!=JsonValueKind.Undefined &&
               (!double.IsFinite(action.Get("not_after_game_minutes").Number(double.NaN)) || action.Get("not_after_game_minutes").Number()<action.Get("not_before_game_minutes").Number(0)))
                throw new InvalidDataException("Invalid authored action end time: "+id);
            if(motor.Get("speed_multiplier").ValueKind!=JsonValueKind.Undefined)
            {
                var speed=motor.Get("speed_multiplier").Number(double.NaN);
                if(!double.IsFinite(speed)||speed<=0||speed>1)throw new InvalidDataException("Invalid movement speed multiplier: "+id);
            }
            var observationTargets=new[]{"observe_actor","observe_fixture","observe_world_object"}.Count(key=>motor.Get(key).Text().Length>0);
            if(observationTargets>1)throw new InvalidDataException("Observation target must have one identity: "+id);
            if(observationTargets>0)
            {
                var distance=motor.Get("observation_distance_m").Number(1.5);
                if(!double.IsFinite(distance)||distance<=0 || action.Get("kind").Text() is not ("inspect" or "take" or "interact"))
                    throw new InvalidDataException("Invalid explicit observation target: "+id);
            }
            var group=motor.Get("observe_group").Items().Select(item=>item.Text()).ToArray();
            if(group.Length>32 || group.Distinct(StringComparer.Ordinal).Count()!=group.Length || group.Any(string.IsNullOrWhiteSpace) ||
               group.Length>0 && (kind!="inspect" || !double.IsFinite(motor.Get("observation_group_distance_m").Number(double.NaN)) || motor.Get("observation_group_distance_m").Number()<=0))
                throw new InvalidDataException("Invalid group observation: "+id);
            if(action.Get("host_execution").Flag() && motor.ValueKind==JsonValueKind.Object &&
               !motor.Get("target_current").Flag() && !action.Get("timing").Get("host_elapsed").Flag() &&
               motor.Get("object_id").Text().Length==0)
                throw new InvalidDataException("A target interaction needs a motor object identity: "+id);
            var precondition = action.Get("precondition");
            if (precondition.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Action needs a declared knowledge gate: " + id);
            var gate = Condition.Compile(precondition, subject);
            var recognition=action.Get("recognize_when").ValueKind==JsonValueKind.Object?Condition.Compile(action.Get("recognize_when"),subject):null;
            if(action.Get("recognize_when").ValueKind is not (JsonValueKind.Undefined or JsonValueKind.Object))
                throw new InvalidDataException("Action recognition must be an explicit knowledge condition: "+id);
            foreach (var reference in action.Get("grants").Items().Concat(action.Get("failure_grants").Items()))
                _ = FieldKey.Read(reference, subject);
            var raw = action.Get("duration");
            var seconds=action.Get("duration_seconds");
            var authoredTime = seconds.ValueKind==JsonValueKind.Number?seconds.GetDouble()/unit:raw.ValueKind == JsonValueKind.Number ? raw.GetDouble()
                : costs.Get(kind).Get("actual").Get("time").Number(double.NaN);
            var multiplier = seconds.ValueKind==JsonValueKind.Number?1:timing.Get("kind_duration_multipliers").Get(kind).Number(1);
            var duration = Math.Max(minimum, authoredTime * unit * multiplier);
            if (!double.IsFinite(authoredTime) || authoredTime < 0 || !double.IsFinite(duration) || multiplier <= 0)
                throw new InvalidDataException("Action needs a finite DV duration: " + id);
            var declaration = JsonNode.Parse(action.GetRawText())!.AsObject();
            var lawId = action.Get("law").Text();
            if (lawId.Length > 0)
            {
                var adoption = world.Get("adoptions").Get(lawId);
                if (!adoption.Get("active").Flag(true) || adoption.Get("mode").Text() != "enforce")
                    throw new InvalidDataException("Action has no active objective enforcement law: " + id);
                var law = adoption.Get("law");
                declaration["objective_gate"] = JsonNode.Parse(law.Get("premise").GetRawText());
                declaration["effects"] = JsonNode.Parse(law.Get("effects").GetRawText());
                if (law.Get("postcondition").ValueKind == JsonValueKind.Object)
                    declaration["objective_postcondition"] = JsonNode.Parse(law.Get("postcondition").GetRawText());
            }
            else if (action.Get("effects").ValueKind == JsonValueKind.Array && action.Get("effects").GetArrayLength() != 0)
                throw new InvalidDataException("Physical effects require an objective law: " + id);
            if (action.Get("authority_precondition").ValueKind == JsonValueKind.Object)
            {
                var premises = new JsonArray();
                if (declaration["objective_gate"] is { } existing) premises.Add(existing.DeepClone());
                premises.Add(JsonNode.Parse(action.Get("authority_precondition").GetRawText()));
                declaration["objective_gate"] = new JsonObject { ["op"] = "all", ["items"] = premises };
            }
            var opportunity=action.Get("interruptible_opportunity");
            if(opportunity.ValueKind!=JsonValueKind.Undefined)
            {
                if(opportunity.ValueKind!=JsonValueKind.Object||string.IsNullOrWhiteSpace(opportunity.Get("reason").Text())||
                   string.IsNullOrWhiteSpace(opportunity.Get("label").Text())||opportunity.Get("lost_when").ValueKind!=JsonValueKind.Object||declaration["objective_gate"] is null)
                    throw new InvalidDataException("An interruptible opportunity needs a named, explicit lost condition: "+id);
                var lost=Condition.Compile(opportunity.Get("lost_when"),"world").Inputs.Distinct().ToArray();
                var objective=Condition.Compile(JsonSerializer.SerializeToElement(declaration["objective_gate"]),"world").Inputs.ToHashSet();
                if(lost.Length==0||lost.Any(key=>!objective.Contains(key)))
                    throw new InvalidDataException("Opportunity loss must read its own objective precondition fields: "+id);
            }
            declaration["requires_host_completion"] = action.Get("travel").ValueKind == JsonValueKind.Object ||
                action.Get("host_execution").Flag();
            result.Add(new(id, gate, duration, action.Get("priority").Number(), JsonSerializer.SerializeToElement(declaration),recognition));
        }
        return result;
    }
}
