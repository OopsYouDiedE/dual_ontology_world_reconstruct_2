using System.Text.Json;
using System.Text.Json.Serialization;

namespace DuelView.Runtime;

public sealed record AutonomyPhaseView(
    [property:JsonPropertyName("active")] bool Active,
    [property:JsonPropertyName("start_minutes")] double? StartMinutes,
    [property:JsonPropertyName("label")] string Label,
    [property:JsonPropertyName("description")] string Description,
    [property:JsonPropertyName("task_guidance")] bool TaskGuidance);

public sealed record CampaignProgressView(
    [property:JsonPropertyName("mode")] string Mode,
    [property:JsonPropertyName("completed")] bool Completed,
    [property:JsonPropertyName("window_completed")] bool WindowCompleted,
    [property:JsonPropertyName("end_minutes")] double EndMinutes,
    [property:JsonPropertyName("label")] string Label,
    [property:JsonPropertyName("phase")] AutonomyPhaseView Phase);

/// <summary>Authored session boundaries. Reaching an observation boundary is
/// separate from any assertion about the quality or emergence of its outcome.</summary>
public static class CampaignProgress
{
    private static FieldKey CompletionFact(JsonElement reference)
    {
        // The campaign manifest predates typed law references. Preserve its
        // existing object/facet/field shape without weakening law access rules.
        var scope=reference.Get("subject").Text();var type=reference.Get("type").Text();
        var key=new FieldKey(reference.Get("object").Text(),reference.Get("facet").Text(),reference.Get("field").Text());
        if(scope.Length>0&&scope!="world"||type.Length>0&&type!="ref"||string.IsNullOrWhiteSpace(key.Object)||string.IsNullOrWhiteSpace(key.Facet)||string.IsNullOrWhiteSpace(key.Field))
            throw new InvalidDataException("Invalid campaign completion fact.");
        return key;
    }
    public static void Validate(JsonElement declaration)
    {
        var completion=declaration.Get("completion");
        if(completion.ValueKind==JsonValueKind.Object)
        {
            var mode=completion.Get("mode").Text("facts");
            if(mode=="facts")
            {
                var facts=completion.Get("facts").Items().ToArray();
                if(facts.Length==0)throw new InvalidDataException("Fact completion requires a nonempty set of facts.");
                foreach(var item in facts)_=CompletionFact(item);
            }
            else if(mode=="observation_window")
            {
                var end=completion.Get("end_minutes").Number(double.NaN);
                var horizon=declaration.Get("run").Get("end_minutes").Number(double.NaN);
                if(!double.IsFinite(end)||end<=declaration.Get("physical").Get("time").Number()||!double.IsFinite(horizon)||horizon<end)
                    throw new InvalidDataException("Observation completion requires a reachable finite time boundary.");
                if(completion.Get("facts").Items().Any())throw new InvalidDataException("Observation completion cannot also require story outcome facts.");
            }
            else throw new InvalidDataException("Unknown completion mode: "+mode);
        }
        var phase=declaration.Get("autonomy_phase");
        if(phase.ValueKind==JsonValueKind.Object)
        {
            var start=phase.Get("start_minutes").Number(double.NaN);
            if(!double.IsFinite(start)||start<0||start>=declaration.Get("run").Get("end_minutes").Number(double.NaN)||
               phase.Get("task_guidance").ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new InvalidDataException("Autonomy phase requires a finite start and an explicit task guidance policy.");
        }
    }

    public static CampaignProgressView Evaluate(JsonElement declaration,RuntimeSession session)
    {
        var completion=declaration.Get("completion");
        var mode=completion.ValueKind==JsonValueKind.Object?completion.Get("mode").Text("facts"):"none";
        var end=mode=="observation_window"?completion.Get("end_minutes").Number():declaration.Get("run").Get("end_minutes").Number();
        var window=mode=="observation_window"&&session.ContentTime>=end;
        var facts=completion.Get("facts").Items().ToArray();
        var completed=window||mode=="facts"&&facts.Length>0&&facts.All(reference=>
            session.World.Read(CompletionFact(reference)) is {Known:true,Conflicted:false} fact&&fact.Value.ValueKind==JsonValueKind.True);
        var phase=declaration.Get("autonomy_phase");
        var active=phase.ValueKind==JsonValueKind.Object&&session.ContentTime>=phase.Get("start_minutes").Number();
        return new(mode,completed,window,end,completion.Get("label").Text(),new(active,
            phase.ValueKind==JsonValueKind.Object?phase.Get("start_minutes").Number():null,
            phase.Get("label").Text(),phase.Get("description").Text(),!active||phase.Get("task_guidance").ValueKind!=JsonValueKind.False));
    }
}
