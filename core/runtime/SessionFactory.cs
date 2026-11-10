using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Runtime;

/// <summary>The same declaration-to-session path is used by both production hosts.</summary>
public static class SessionFactory
{
    public static RuntimeSession Create(RuntimeContent content, JsonElement scene, string viewer, bool autonomousViewer = false)
    {
        scene = SceneComposer.Materialize(scene);
        var policy = content.Data(content.Manifest.Get("runtime_definition").Text());
        var timing = content.Data(policy.Get("action_timing_definition").Text());
        var unit = timing.Get("content_time_unit_seconds").Number(double.NaN);
        if (!double.IsFinite(unit) || unit <= 0) throw new InvalidDataException("Content time unit must be positive.");
        var effective = JsonNode.Parse(policy.GetRawText())!.AsObject();
        effective["content_time_unit_seconds"] = unit;
        if (scene.Get("clock_ref").ValueKind == JsonValueKind.Object)
            effective["clock_ref"] = JsonNode.Parse(scene.Get("clock_ref").GetRawText());
        var world = scene.Get("physical");
        if (world.Get("domain").Text() != "physical") throw new InvalidDataException("Session needs an objective physical world.");
        var session = new RuntimeSession(world, JsonSerializer.SerializeToElement(effective),
            content.Data(policy.Get("scheduling_definition").Text()), content.Data(policy.Get("clock_definition").Text()),
            content.Data(policy.Get("residency_definition").Text()), world.Get("time").Number() * unit);
        session.ConfigureBindings(scene.Get("bindings"));
        var costs = scene.Get("cost_model");
        var foundViewer = false;
        foreach (var declaration in scene.Get("actors").Items())
        {
            var id = declaration.Get("id").Text();
            var actor = JsonNode.Parse(declaration.GetRawText())!.AsObject();
            var authored = content.Document.Root.Get("characters").Get(id);
            if (authored.Get("autonomy").ValueKind == JsonValueKind.Object)
                actor["autonomy"] = JsonNode.Parse(authored.Get("autonomy").GetRawText());
            var normalized = JsonSerializer.SerializeToElement(actor);
            var attentionId = policy.Get("actor_attention_overrides").Get(id).Text(policy.Get("attention").Text());
            session.RegisterActor(normalized, content.Data(attentionId), ActionCatalog.Compile(normalized, world, costs, timing), id != viewer || autonomousViewer);
            foundViewer |= id == viewer;
        }
        if (!foundViewer) throw new InvalidDataException("Viewer is absent from the scene.");
        session.ConfigureMechanics(scene);
        foreach (var process in scene.Get("world_processes").Items())
        {
            var id = process.Get("law").Text();
            var adoption = world.Get("adoptions").Get(id);
            if (adoption.ValueKind != JsonValueKind.Object) throw new InvalidDataException("World process has no adopted law: " + id);
            var automatic = JsonNode.Parse(adoption.GetRawText())!.AsObject();
            automatic["trigger"] = process.Get("once").Flag() ? "once" : "rising_edge";
            var reference = scene.Get("clock_ref");
            if (reference.ValueKind != JsonValueKind.Object) throw new InvalidDataException("World processes need a declared clock.");
            session.Rules.Register(id, JsonSerializer.SerializeToElement(automatic), FieldKey.Read(reference, "world"));
        }
        return session;
    }
}
