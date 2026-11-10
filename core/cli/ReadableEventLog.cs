using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using DuelView.Runtime;

/// <summary>A viewer-safe reading copy of completed production receipts, never a replay.</summary>
internal static class ReadableEventLog
{
    sealed record Row(Dictionary<string, JsonElement> Values, string File, long Line);
    sealed record Input(string Path, List<Row> Rows, int IncompleteBlocks, int InvalidBlocks);
    sealed class Entry
    {
        public double time { get; init; }
        public string actor_name { get; init; } = "";
        public string kind { get; init; } = "";
        public string label { get; set; } = "";
        public string outcome { get; init; } = "";
        public string summary { get; set; } = "";
        public List<object> source_refs { get; } = [];
        public List<object> details { get; } = [];
        public int source_count => source_refs.Count;
    }
    static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping, MaxDepth = 256
    };
    static JsonElement Get(JsonElement value, string name) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var found) ? found : default;
    static JsonElement Get(Row row, string name) => row.Values.GetValueOrDefault(name);
    static string Text(JsonElement value, string fallback = "") => value.ValueKind == JsonValueKind.String ? value.GetString() ?? fallback : fallback;
    static double Number(JsonElement value, double fallback = 0) => value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number) ? number : fallback;
    static IEnumerable<JsonElement> Items(JsonElement value) => value.ValueKind == JsonValueKind.Array ? value.EnumerateArray() : [];
    static int Day(double minutes) => (int)Math.Floor(minutes / 1440) + 1;
    static string Clock(double minutes)
    {
        var whole = (long)Math.Floor(minutes);
        return $"第{Day(minutes)}日 {whole / 60 % 24:00}:{whole % 60:00}";
    }
    static string Scalar(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.True => "是", JsonValueKind.False => "否", JsonValueKind.String => value.GetString() ?? "",
        JsonValueKind.Number => value.GetRawText(), JsonValueKind.Null => "未记录", _ => "详见来源"
    };
    static string FactId(JsonElement reference)
    {
        string Part(string lower, string upper) => Text(Get(reference, lower), Text(Get(reference, upper)));
        return Part("object", "Object") + "." + Part("facet", "Facet") + "." + Part("field", "Field");
    }
    static string Sha(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).ToLowerInvariant();

    static Input Read(string path)
    {
        var rows = new List<Row>(); var current = new Dictionary<string, JsonElement>();
        var lineNumber = 0L; var firstLine = 0L; var invalid = false; var invalidBlocks = 0;
        if (!File.Exists(path)) return new(path, rows, 0, 0);
        foreach (var line in File.ReadLines(path))
        {
            ++lineNumber;
            if (string.IsNullOrWhiteSpace(line))
            {
                if (current.Count > 0 || invalid)
                {
                    if (!invalid && current.ContainsKey("receipt_index") && current.ContainsKey("start_time") && current.ContainsKey("actor"))
                        rows.Add(new(current, Path.GetFileName(path), firstLine));
                    else ++invalidBlocks;
                }
                current = new(); invalid = false; firstLine = 0; continue;
            }
            if (firstLine == 0) firstLine = lineNumber;
            var text = line.StartsWith("- ", StringComparison.Ordinal) ? line[2..] : line.TrimStart();
            var split = text.IndexOf(": ", StringComparison.Ordinal);
            if (split < 0) { invalid = true; continue; }
            try { using var json = JsonDocument.Parse(text[(split + 2)..]); current[text[..split]] = json.RootElement.Clone(); }
            catch (JsonException) { invalid = true; }
        }
        // A partial final record is coverage information, never an inferred completion.
        return new(path, rows, current.Count > 0 || invalid ? 1 : 0, invalidBlocks);
    }

    static object Source(Row row) => new
    {
        file = row.File, line = row.Line, receipt_index = Number(Get(row, "receipt_index")),
        evidence_id = Text(Get(row, "evidence_id")), execution = Number(Get(row, "execution_event"))
    };
    static string Outcome(string value) => value switch
    {
        "completed" => "已完成", "deduction_unproved" => "证据不足", "suggestion_rejected" => "建议未获采纳",
        "incantation_precondition_failed" => "言灵条件未满足", _ => "未完成"
    };
    static string MechanicSummary(JsonElement mechanic, IReadOnlyDictionary<string, string> names)
    {
        var kind = Text(Get(mechanic, "Kind"), Text(Get(mechanic, "kind")));
        var data = Get(mechanic, "Details"); if (data.ValueKind != JsonValueKind.Object) data = Get(mechanic, "details");
        var success = Get(mechanic, "Success"); if (success.ValueKind == JsonValueKind.Undefined) success = Get(mechanic, "success");
        if (kind == "deduction")
        {
            var evidence = Items(Get(data, "evidence")).ToArray();
            var sources = evidence.SelectMany(item => Items(Get(item, "source_ids"))).Select(item => Text(item)).Where(item => item.Length > 0).Distinct().Count();
            var result = success.ValueKind == JsonValueKind.True ? "推演成立" : "所选证据尚不能证明结论";
            var qualification = Text(Get(data, "qualification"));
            return $"{result}；本次使用 {evidence.Length} 项本人已知证据，关联 {sources} 条来源。" +
                (success.ValueKind == JsonValueKind.True && qualification.Length > 0 ? "结论边界：" + qualification : "");
        }
        if (kind == "suggestion")
        {
            var target = Text(Get(data, "target"));
            var accepted = Get(data, "accepted").ValueKind == JsonValueKind.True;
            var reasons = Items(Get(data, "context")).Select(item => Text(item)).Where(item => item.Length > 0).ToArray();
            var score = Get(data,"score").ValueKind==JsonValueKind.Number?$"（本人评价 {Number(Get(data,"score")):0.##}，接受门槛 {Number(Get(data,"threshold")):0.##}）":"";
            return $"{names.GetValueOrDefault(target, target)}{(accepted ? "采纳了建议" : "暂未采纳建议")}{score}。" +
                (reasons.Length > 0 ? "当下考虑：" + string.Join("；", reasons) + "。" : "") +
                (!accepted ? "本次没有获得协作结果，可在取得证据或改变风险后再提议。" : "");
        }
        if (kind == "incantation")
        {
            var backlash = Get(data, "backlash");
            return $"规则已生效；消耗专注 {Number(Get(data, "cost")):0.##}，剩余 {Number(Get(data, "resource_remaining")):0.##}；" +
                $"反噬增加 {Number(Get(backlash, "amount")):0.##}，累计 {Number(Get(backlash, "total")):0.##}。" +
                $"临时规则到期：{Clock(Number(Get(data, "expires")))}；以实际到期回执为准。";
        }
        if (kind == "strategy") return "已根据本人掌握的条件完成方案比较；实际选定结果保留在详情中。";
        return "";
    }

    public static void Write(string source, JsonElement content, string destination)
    {
        var viewer = Text(Get(content, "viewer"), "detective");
        var actors = Items(Get(content, "actors")).ToArray();
        var names = actors.ToDictionary(a => Text(Get(a, "id")), a => Text(Get(a, "name"), Text(Get(a, "id"))), StringComparer.Ordinal);
        var actionMap = actors.SelectMany(a => Items(Get(a, "actions"))).ToDictionary(a => Text(Get(a, "id")), StringComparer.Ordinal);
        var taskLabels = actors.Where(actor => Text(Get(actor, "id")) == viewer).SelectMany(actor => Items(Get(Get(actor, "planning"), "tasks")))
            .ToDictionary(task => Text(Get(task, "id")), task => Text(Get(task, "label")), StringComparer.Ordinal);
        var labels = Get(content, "fact_labels");
        var roomLabels = Get(content, "room_labels");
        var hidden = Items(Get(Get(content, "display"), "hidden_facts")).Select(item => Text(item)).ToHashSet(StringComparer.Ordinal);
        var actionInput = Read(source); var stateInput = Read(Path.ChangeExtension(source, "states.yaml"));
        var auditPath=Path.ChangeExtension(source,"evidence-coverage.json");
        JsonElement audit=default;
        if(File.Exists(auditPath)){using var auditDocument=JsonDocument.Parse(File.ReadAllText(auditPath));audit=auditDocument.RootElement.Clone();}
        var expectedHash=Text(Get(Get(audit,"state_log"),"sha256"));
        var auditConsistent=expectedHash.Length>0&&File.Exists(stateInput.Path)&&expectedHash==Sha(stateInput.Path)&&
            Number(Get(Get(audit,"state_log"),"rows"))==stateInput.Rows.Count&&Get(audit,"complete").ValueKind==JsonValueKind.True;
        var entries = new List<Entry>(); var hiddenRows = 0;
        var displayedUtterances = new HashSet<string>(StringComparer.Ordinal);
        foreach (var row in actionInput.Rows)
        {
            foreach(var line in Items(Get(row,"narrative")))
            {
                if(!Items(Get(line,"Recipients")).Any(recipient=>Text(recipient)==viewer))continue;
                var evidenceId=Text(Get(line,"EvidenceId"));
                if(evidenceId.Length>0&&!displayedUtterances.Add(evidenceId))continue;
                var speech=Text(Get(line,"Kind"))=="speech";
                var narrativeEntry=new Entry{time=Number(Get(row,"start_time"))+Number(Get(row,"duration")),
                    actor_name=Text(Get(line,"SpeakerLabel"),"在场者"),kind=speech?"dialogue":"reflection",
                    label=speech?"当场说出":"当时所想",outcome="已发生",summary=Text(Get(line,"Text"))};
                narrativeEntry.source_refs.Add(Source(row));
                narrativeEntry.details.Add(new{evidence_id=evidenceId,speaker=Text(Get(line,"Speaker")),scope=speech?"本人实际在场听到":"本人私有记述"});
                entries.Add(narrativeEntry);
            }
            // Author logs contain NPC internal actions. A player reading copy cannot disclose them.
            if (Text(Get(row, "actor")) != viewer) { ++hiddenRows; continue; }
            var id = Text(Get(row, "action")); var declaration = actionMap.GetValueOrDefault(id);
            var mechanics = Items(Get(row, "mechanics")).Where(item => Text(Get(item, "Actor"), Text(Get(item, "actor"))) == viewer)
                .Select(item=>
                {
                    var mechanicKind=Text(Get(item,"Kind"),Text(Get(item,"kind")));
                    var field=Get(item,"Details").ValueKind==JsonValueKind.Object?"Details":"details";
                    return JsonSerializer.SerializeToElement(item.EnumerateObject().ToDictionary(property=>property.Name,
                        property=>property.Name==field?RuntimeSession.ProjectMechanicDetails(mechanicKind,property.Value,viewer):property.Value));
                }).ToArray();
            var kind = mechanics.Length > 0 ? Text(Get(mechanics[0], "Kind"), Text(Get(mechanics[0], "kind"))) : "action";
            if (kind == "suggestion") kind = "opinion";
            if (kind == "strategy") kind = "action";
            var label = Text(Get(row, "label"), Text(Get(declaration, "label"), "本人行动"));
            var declaredKind = Text(Get(declaration, "kind"));
            if (kind == "action" && (declaredKind == "rest" || label is "歇息" or "饮水" or "饮茶" or "清洗" or "洗漱" or "小憩")) kind = "routine";
            var duration = Number(Get(row, "duration"));
            var summary = string.Join(" ", mechanics.Select(item => MechanicSummary(item, names)).Where(item => item.Length > 0));
            if (summary.Length == 0 && duration > 0) summary = $"实际耗时 {duration.ToString("0.##", CultureInfo.InvariantCulture)} 分钟。";
            var interruptionLabel=Text(Get(Get(row,"interruption"),"Label"));
            if(interruptionLabel.Length>0)summary+=" 现场机会变化，行动未完成："+interruptionLabel+"。";
            var intent = Get(row, "decision_intent"); var path = Text(Get(intent, "Path"));
            if (path == "task") summary += " 当前任务：" + taskLabels.GetValueOrDefault(Text(Get(intent, "Task")), "推进已知目标") + "。";
            else if (path == "physiology")
            {
                var need = Text(Get(intent, "PhysiologicalNeed")) switch { "energy" => "休息", "hunger" => "进食", "thirst" => "饮水", "hygiene" => "清洁", _ => "身体照护" };
                summary += " 本次优先处理" + need + (Text(Get(intent,"Task")).Length>0?"；已有任务保留，等待适合续接的条件。":"。");
            }
            else if (path == "player") summary += " 本次由玩家决定。";
            else if (path == "goal") summary += " 本次按自身目标选择下一步；方案是预测，结果由实际行动检验。";
            var entry = new Entry { time = Number(Get(row, "start_time")), actor_name = names.GetValueOrDefault(viewer, viewer), kind = kind,
                label = label, outcome = Outcome(Text(Get(row, "outcome"))), summary = summary };
            entry.source_refs.Add(Source(row));
            entry.details.Add(new { action = id, duration, room = Text(Get(row, "room")), mechanics,
                decision_intent = intent.ValueKind == JsonValueKind.Undefined ? (object?)null : intent, reason = Text(Get(row, "reason")) });
            entries.Add(entry);
        }
        var groups = new Dictionary<string, Entry>(StringComparer.Ordinal);
        foreach (var row in stateInput.Rows)
        {
            if (Text(Get(row, "actor")) != viewer) { ++hiddenRows; continue; }
            var field = Get(row, "fact_ref"); var fact = FactId(field);
            if (Text(Get(row,"kind"))=="internal_state"||displayedUtterances.Contains(Text(Get(row,"evidence_id")))||hidden.Contains(fact) || fact.EndsWith(".room", StringComparison.Ordinal) || fact.EndsWith(".spot", StringComparison.Ordinal)) { ++hiddenRows; continue; }
            var time = Number(Get(row, "start_time")); var kind = Text(Get(row, "kind"));
            var origin = Get(row, "source"); var speaker = Text(Get(origin, "actor"));
            var action = Text(Get(row, "action")); var value = Get(row, "fact_value");
            var expiry = Get(origin, "expired_at").ValueKind == JsonValueKind.Number;
            var world = Get(origin, "id").ValueKind == JsonValueKind.String && Get(origin, "label").ValueKind == JsonValueKind.String;
            var label = Text(Get(row, "label"));
            string message;
            if (expiry) message = "本人收到临时封隔规则到期的反馈；后续安全依赖实际机械措施或值守。";
            else if (world) message = Text(Get(origin, "label"));
            else if (value.ValueKind == JsonValueKind.String) message = Text(Get(roomLabels, value.GetString() ?? ""), value.GetString() ?? "");
            else if (Text(Get(labels, fact)) is { Length: > 0 } fieldLabel) message = fieldLabel + "：" + Scalar(value);
            else if (kind is "deduction" or "inference")
            {
                var basis = Get(origin, "basis");
                message = Text(Get(basis, "conclusion"));
                if (message.Length == 0 && actionMap.TryGetValue(action, out var own) && action.StartsWith(viewer + ".", StringComparison.Ordinal))
                    message = Text(Get(Get(own, "deduction"), "title"), Text(Get(own, "label"), "新增一项推演认知"));
                if (message.Length == 0) message = "新增一项有来源的推理认知";
            }
            else if (kind == "opinion") message = Get(origin, "accepted").ValueKind == JsonValueKind.True ? "本次建议得到采纳" : "本次建议未获采纳";
            else if (kind == "incantation") message = "言灵代价与局部规则已反馈给本人";
            else
            {
                var bracket = label.IndexOf(']');
                message = bracket >= 0 ? label[(bracket + 1)..].Trim() : label;
                if (kind.StartsWith("buff_", StringComparison.Ordinal)) message = message.Split('｜')[0];
                if (message.EndsWith("状态更新", StringComparison.Ordinal) || message is "true" or "false" || message.Length == 0)
                    message = actionMap.TryGetValue(action, out var own) && action.StartsWith(viewer + ".", StringComparison.Ordinal)
                        ? Text(Get(own, "label"), "本次查验") + "：相关状态已反馈" : "收到一项状态变化，保留原始来源";
            }
            var publicKind = expiry ? "incantation" : world ? "world_event" : kind switch { "deduction" or "inference" => "deduction", "opinion" => "opinion", "incantation" => "incantation", _ => "evidence" };
            var received = kind == "communication_received" && speaker != viewer;
            var speakerName=Text(Get(origin,"speaker_label"),speaker.Length>0?names.GetValueOrDefault(speaker,speaker):"来源未注明");
            var originLabel = expiry ? "临时规则到期" : world ? "实际感知" : received ? (speaker.Length>0&&speaker==Text(Get(field,"Object"))?"本人自述 · ":"他人转述 · ")+speakerName : kind switch
            { "deduction" or "inference" => "推演所得", "perception" => "实际感知", "opinion" => "意见回执", "incantation" => "言灵回执",
                "buff_added" => "新增感受与倾向", "buff_removed" => "影响已解除", "emotion_changed" => "情绪变化", _ => "亲见与交互所得" };
            var sourceKey = origin.ValueKind == JsonValueKind.Object ? origin.GetRawText() : Text(Get(row, "action"));
            var key = Day(time) + "/" + time.ToString("R", CultureInfo.InvariantCulture) + "/" + kind + "/" + sourceKey;
            if (!groups.TryGetValue(key, out var entry))
            {
                entry = new Entry { time = time, actor_name = names.GetValueOrDefault(viewer, viewer), kind = publicKind,
                    label = originLabel, outcome = expiry ? "已到期" : "已获知", summary = message };
                groups[key] = entry; entries.Add(entry);
            }
            else if (!entry.summary.Split("；").Contains(message, StringComparer.Ordinal)) entry.summary += "；" + message;
            entry.source_refs.Add(Source(row));
            // Other people's internal action IDs and arbitrary source payloads are not player-visible.
            entry.details.Add(new
            {
                evidence_id = Text(Get(row, "evidence_id")), fact_ref = fact, value = value.ValueKind == JsonValueKind.Undefined ? (object?)null : value,
                original_label = label, recorded_kind = kind,
                source_actor = speaker.Length > 0 ? names.GetValueOrDefault(speaker, speaker) : "环境或本人交互",
                source_action = speaker == viewer ? action : "", channel = Text(Get(origin, "channel")),
                source_execution = Number(Get(origin, "execution"))
            });
        }
        foreach (var routine in entries.Where(item => item.kind == "routine").GroupBy(item => (Day(item.time), item.label, item.outcome)).Where(group => group.Count() > 1).ToArray())
        {
            var ordered = routine.OrderBy(item => item.time).ToArray(); var first = ordered[0];
            first.label += $"（同日 {ordered.Length} 次）";
            first.summary = $"记录范围：{Clock(first.time)} 至 {Clock(ordered[^1].time)}；每次实际耗时与回执均保留在详情中。";
            foreach (var other in ordered.Skip(1))
            {
                first.source_refs.AddRange(other.source_refs);
                first.details.Add(new { time = other.time, records = other.details });
                entries.Remove(other);
            }
        }
        entries = entries.OrderBy(item => item.time).ThenBy(item => item.kind == "action" ? 0 : 1).ToList();
        object Coverage(Input input) => new
        {
            path = input.Path, present = File.Exists(input.Path), sha256 = File.Exists(input.Path) ? Sha(input.Path) : "",
            complete_rows = input.Rows.Count, excluded_incomplete_blocks = input.IncompleteBlocks, excluded_invalid_blocks = input.InvalidBlocks,
            first_game_minute = input.Rows.Count > 0 ? (double?)input.Rows.Min(row => Number(Get(row, "start_time"))) : null,
            last_game_minute = input.Rows.Count > 0 ? (double?)input.Rows.Max(row => Number(Get(row, "start_time"))) : null
        };
        var sidecar = Path.ChangeExtension(destination, "events.json");
        var document = new
        {
            schema = "readable-event-log-v1", viewer, scenario = Text(Get(content, "scenario_label"), "会话行记"),
            gameplay_accepted = false, coverage = new { actions = Coverage(actionInput), states = Coverage(stateInput),
                committed_evidence_audit=new {present=audit.ValueKind==JsonValueKind.Object,cryptographic_comparison_available=expectedHash.Length>0,consistent=expectedHash.Length>0?(bool?)auditConsistent:null},
                shown_viewer_entries = entries.Count, excluded_nonviewer_or_hidden_rows = hiddenRows },
            entries, limitations = new[] { "只包含原文件完整记录；原行动与状态记录覆盖可能不同。", "状态记录不补写为缺失的已完成行动。", "此阅读副本不展示 NPC 私有行动、意图或评分；不作五日验收判定。" }
        };
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(destination))!);
        File.WriteAllText(sidecar, JsonSerializer.Serialize(document, Json) + "\n", new UTF8Encoding(false));
        var output = new StringBuilder();
        output.AppendLine(Text(Get(content, "scenario_label"), "安眠者有福") + " · " + names.GetValueOrDefault(viewer, viewer) + "行记");
        output.AppendLine("仅记录本人行动、亲见、实际收到的转述与推演。未知线索和他人暗谋不在本行记中。原始机器记录保持不变。");
        output.AppendLine($"覆盖：行动原记录 {actionInput.Rows.Count} 条，认知／状态原记录 {stateInput.Rows.Count} 条；下列本人阅读条目 {entries.Count} 组。");
        if(expectedHash.Length>0)output.AppendLine(auditConsistent?"已与宿主关闭时的认知逐条计数、文件行数及 SHA-256 完整性记录相符。":"认知记录与宿主关闭时的完整性记录不一致，不能据此声称记录完整。");
        output.AppendLine($"未纳入尾部不完整记录 {actionInput.IncompleteBlocks + stateInput.IncompleteBlocks} 块，无法解析记录 {actionInput.InvalidBlocks + stateInput.InvalidBlocks} 块。两份原记录的时间范围与 SHA-256 见 {Path.GetFileName(sidecar)}。");
        output.AppendLine("未记录不等于未发生；认知回执也不等于相应行动日志完整。本文件不颁发流程验收结论。\n");
        var lastDay = -1;
        foreach (var entry in entries)
        {
            if (lastDay != Day(entry.time)) { lastDay = Day(entry.time); output.AppendLine($"\n第 {lastDay} 日\n"); }
            output.Append(Clock(entry.time)).Append(" · ").Append(entry.actor_name).Append(" · ").Append(entry.label).Append("（").Append(entry.outcome).AppendLine("）");
            if (entry.summary.Length > 0) output.AppendLine("  " + entry.summary);
            if (entry.source_count > 1) output.AppendLine($"  同次来源合并 {entry.source_count} 条；原始引用保留在详情文件。");
        }
        File.WriteAllText(destination, output.ToString(), new UTF8Encoding(false));
    }

    public static void Render(string[] args)
    {
        if (args.Length != 4) throw new ArgumentException("--render-cli-log <actions.yaml> <content.dv> <output.txt>");
        string ReadContent(string resource) => File.ReadAllText(resource.StartsWith("res://", StringComparison.Ordinal) ? resource[6..] : resource);
        var content = CharacterContentRevisions.Capture(args[2].StartsWith("res://", StringComparison.Ordinal) ? args[2] : "res://" + args[2].Replace('\\', '/'), ReadContent).Definition;
        Write(args[1], content.Declaration, args[3]);
        Console.WriteLine(Path.GetFullPath(args[3]));
        Console.WriteLine(Path.GetFullPath(Path.ChangeExtension(args[3], "events.json")));
    }
}
