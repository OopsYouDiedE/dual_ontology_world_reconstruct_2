using System.Text.Json;
using DuelView.Runtime;
using Godot;

namespace DualOntologyWorldReconstruct2;

public partial class CampaignBridge : Node
{
    private CharacterSessionDefinition? definition;
    private RuntimeSession? session;
    private readonly Dictionary<long, Decision> decisions = [];
    private readonly List<ActionReceipt> receipts = [];
    private string contentPath = "res://assets/data/scenarios/campaign.dv";
    private string error = "";
    private string viewer = "detective";
    private bool autonomous;
    private string notes = "";
    private static string Read(string path) => System.IO.File.ReadAllText(ProjectSettings.GlobalizePath(path));
    private static string Encode(object value) => JsonSerializer.Serialize(value);
    private static string String(JsonElement value, string key, string fallback = "")
        => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() ?? fallback : fallback;
    private static IEnumerable<JsonElement> Items(JsonElement value, string key)
        => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var items) && items.ValueKind == JsonValueKind.Array ? items.EnumerateArray() : [];
    private static RuntimeSession Create(CharacterSessionDefinition prepared)
    {
        var runtime = prepared.Create();
        if (runtime.IsLifeSession) throw new InvalidDataException("生活内容请从生活入口打开。");
        foreach (var item in Items(prepared.Declaration, "deductions")) runtime.ConfigureDeduction(Read(String(item, "source")), item);
        foreach (var item in Items(prepared.Declaration, "strategy_activities")) runtime.ConfigureStrategy(Read(String(item, "source")), item);
        return runtime;
    }

    public string Open(string path = "")
    {
        try
        {
            var destination = string.IsNullOrWhiteSpace(path) ? contentPath : path;
            var prepared = new CharacterSessionDefinition(Read(destination), Read("res://assets/data/98-runtime-session.data.dv"), Read);
            var replacement = Create(prepared);
            var player = String(prepared.Declaration, "viewer", "detective");
            _ = replacement.View(player);
            replacement.SetAutonomy(player, false);
            contentPath = destination;
            definition = prepared;
            session = replacement;
            viewer = player;
            autonomous = false;
            notes = "";
            decisions.Clear();
            receipts.Clear();
            error = "";
            return Encode(new { ok = true, hash = definition.Hash, status = Status() });
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return Encode(new { ok = false, error });
        }
    }

    public string Step(double seconds = 1.0)
    {
        if (session is null || definition is null) return Encode(new { ok = false, error = "尚未打开案件。" });
        try
        {
            var progress = CampaignProgress.Evaluate(definition.Declaration, session);
            var horizon = definition.Declaration.GetProperty("run").GetProperty("end_minutes").GetDouble();
            if (!progress.Completed && session.ContentTime < horizon)
                session.Step(Math.Min(Math.Clamp(seconds, 0.0, 300.0), (horizon - session.ContentTime) * 60.0), false, false, viewer);
            var dispatch = new List<object>();
            while (session.TryAction(out var decision))
            {
                if (decision is null) continue;
                decisions[decision.Execution] = decision;
                var host = decision.Action.Declaration.TryGetProperty("requires_host_completion", out var required) && required.ValueKind == JsonValueKind.True;
                dispatch.Add(new { execution = decision.Execution, actor = decision.Actor, action = decision.Action.Id, label = String(decision.Action.Declaration, "label"), host_required = host });
            }
            while (session.TryCancellation(out var cancelled))
                if (cancelled is not null) session.ConfirmCancelled(cancelled);
            while (session.TryReceipt(out var receipt))
            {
                if (receipt is null) continue;
                receipts.Add(receipt);
                decisions.Remove(receipt.Execution);
            }
            return Encode(new { ok = true, dispatch, status = Status() });
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return Encode(new { ok = false, error });
        }
    }

    public string Submit(string action, string evidence = "")
    {
        if (session is null) return "尚未打开案件。";
        try
        {
            session.SetAutonomy(viewer, false);
            if (evidence.Length > 0) session.SubmitDeduction(viewer, action, JsonSerializer.Deserialize<string[]>(evidence) ?? []);
            else session.Submit(viewer, action);
            session.SetAutonomy(viewer, autonomous);
            return "";
        }
        catch (Exception exception)
        {
            session.SetAutonomy(viewer, autonomous);
            return exception.Message;
        }
    }

    public string Cancel()
    {
        return session?.RequestCancel(viewer) == true ? "" : "当前没有可取消的行动。";
    }
    public string CompleteHostAction(long execution)
    {
        if (session is null || !decisions.TryGetValue(execution, out var decision)) return "没有可完成的宿主动作。";
        return session.HostCompleted(decision) ? "" : "宿主动作尚未满足完成条件；需要真实房间宿主报告到场。";
    }
    public void SetAutomatic(bool value) { autonomous = value; session?.SetAutonomy(viewer, value); }
    public void SetNotes(string value) => notes = value;
    public string Preview(string action)
    {
        try { return Encode(new { ok = true, preview = session!.DeductionPreview(viewer, action) }); }
        catch (Exception exception) { return Encode(new { ok = false, error = exception.Message }); }
    }

    public string Observe() => Encode(new { ok = session is not null, error, snapshot = Snapshot(), status = Status() });

    private object Status()
    {
        if (session is null || definition is null) return new { active = false, error };
        var progress = CampaignProgress.Evaluate(definition.Declaration, session);
        var horizon = definition.Declaration.GetProperty("run").GetProperty("end_minutes").GetDouble();
        return new { active = !progress.Completed && session.ContentTime < horizon, completed = progress.Completed, progress, time = session.ContentTime, hash = definition.Hash };
    }

    private object Snapshot()
    {
        if (session is null || definition is null) return new { started = false, error };
        var actors = Items(definition.Declaration, "actors").ToArray();
        var profile = actors.Single(actor => String(actor, "id") == viewer);
        var view = session.View(viewer);
        var room = session.World.Read(new FieldKey(viewer, "state", "room"))?.Value.ToString() ?? "";
        return new
        {
            started = true, time = session.ContentTime, viewer, name = String(profile, "name", viewer), room, automatic = autonomous, notes,
            label = String(definition.Declaration, "scenario_label", "案件案卷"),
            needs = session.Needs(viewer), affect = session.Affect(viewer), activity = session.Activity(viewer),
            knowledge = view.Knowledge.Where(item => item.Value.Known).Select(item => new { key = item.Key.ToString(), subject = item.Key.Object, facet = item.Key.Facet, field = item.Key.Field, value = item.Value.Value, confidence = item.Value.Confidence, conflicted = item.Value.Conflicted }).ToArray(),
            evidence = session.Evidence(viewer), map = view.RememberedMap,
            actors = actors.Where(actor => !(actor.TryGetProperty("hidden", out var hidden) && hidden.ValueKind == JsonValueKind.True) && session.World.Read(new FieldKey(String(actor, "id"), "state", "room"))?.Value.ToString() == room)
                .Select(actor => new { id = String(actor, "id"), name = String(actor, "name", String(actor, "id")) }).ToArray(),
            fixtures = Items(definition.Declaration, "fixtures").Where(item => String(item, "room") == room && !(item.TryGetProperty("hidden", out var hidden) && hidden.ValueKind == JsonValueKind.True))
                .Select(item => new { id = String(item, "id"), label = String(item, "label") }).ToArray(),
            actions = Items(profile, "actions").Where(item => session.Available(viewer, String(item, "id")))
                .Select(item => new { id = String(item, "id"), label = String(item, "label", String(item, "id")), kind = String(item, "kind"), target = String(item, "target_object"), deduction = item.TryGetProperty("deduction", out var deduction) && deduction.ValueKind == JsonValueKind.Object }).ToArray(),
            mechanics = session.MechanicHistoryFor(viewer),
            pending = decisions.Values.Where(decision => decision.Actor == viewer).Select(decision => new
            {
                execution = decision.Execution, action = decision.Action.Id,
                host_required = decision.Action.Declaration.TryGetProperty("requires_host_completion", out var required) && required.ValueKind == JsonValueKind.True
            }).ToArray(),
            receipts = receipts.Where(item => item.Actor == viewer).TakeLast(100).ToArray(),
            narrative = receipts.SelectMany(item => item.Narrative ?? []).Where(item => item.Recipients.Contains(viewer, StringComparer.Ordinal)).TakeLast(100).ToArray()
        };
    }

    public string Save(string path)
    {
        if (session is null || definition is null) return "尚未打开案件。";
        try
        {
            var destination = ProjectSettings.GlobalizePath(path);
            var temporary = destination + ".tmp";
            var payload = JsonSerializer.Serialize(new { hash = definition.Hash, content_path = contentPath, state = session.SaveState(), receipts, notes, autonomous });
            System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(destination)!);
            System.IO.File.WriteAllText(temporary, payload);
            System.IO.File.Move(temporary, destination, true);
            return "";
        }
        catch (Exception exception) { return exception.Message; }
    }

    public string Load(string path)
    {
        try
        {
            using var document = JsonDocument.Parse(Read(path));
            var root = document.RootElement;
            var sourcePath = String(root, "content_path", contentPath);
            var replacementDefinition = new CharacterSessionDefinition(Read(sourcePath), Read("res://assets/data/98-runtime-session.data.dv"), Read);
            if (!root.TryGetProperty("hash", out var storedHash) || storedHash.GetString() != replacementDefinition.Hash) return "存档内容版本不同。";
            var replacement = Create(replacementDefinition);
            replacement.RestoreState(root.GetProperty("state").Deserialize<RuntimeSessionState>()!);
            var restoredReceipts = root.TryGetProperty("receipts", out var savedReceipts) ? savedReceipts.Deserialize<ActionReceipt[]>() ?? [] : [];
            var restoredViewer = String(replacementDefinition.Declaration, "viewer", "detective");
            var restoredAutomatic = root.TryGetProperty("autonomous", out var automatic) && automatic.ValueKind == JsonValueKind.True;
            replacement.SetAutonomy(restoredViewer, restoredAutomatic);
            var restoredDecisions = replacement.SaveState().Executions
                .Select(item => replacement.DecisionFor(item.Execution)).Where(item => item is not null).ToDictionary(item => item!.Execution, item => item!);
            definition = replacementDefinition;
            session = replacement;
            contentPath = sourcePath;
            viewer = restoredViewer;
            autonomous = restoredAutomatic;
            notes = String(root, "notes");
            decisions.Clear();
            foreach (var item in restoredDecisions) decisions[item.Key] = item.Value;
            receipts.Clear();
            receipts.AddRange(restoredReceipts);
            error = "";
            return "";
        }
        catch (Exception exception) { return exception.Message; }
    }

    public override void _ExitTree() => session = null;
}
