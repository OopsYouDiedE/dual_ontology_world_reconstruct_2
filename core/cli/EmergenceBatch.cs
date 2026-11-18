using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using DuelView.Runtime;

internal sealed partial class NativeCli
{
    record LabInput(string Actor, string Need, double Delta);
    record LabLink(string Actor, string Action, double CompletedAt, FieldKey Fact, JsonElement Value, string EvidenceId);
    record LabAction(string Actor, string Action, double Start, double End, string[] Alternatives, LabLink[] Observed);
    record LabResponse(LabAction Baseline, LabAction Changed, LabLink[] Links);
    record LabScore(LabResponse[] Responses, int ChangedPeers);
    record LabRun(LabInput? Input, double? InitialValue, double GameTime, bool CampaignCompleted, int UnexpectedFailures,
        string[] InvariantFailures, int SuccessfulActions, string[] Milestones, LabAction[] Actions);
    LabTrace? lab;

    sealed class LabTrace
    {
        readonly Dictionary<FieldKey, (ActionReceipt Receipt, Fact Fact)> writes = new();
        readonly Dictionary<long, (double Start, string[] Alternatives, LabLink[] Links)> pending = new();
        public readonly List<LabAction> Actions = [];

        public void Dispatch(RuntimeSession session, Decision decision)
        {
            var client = session.View(decision.Actor);
            var evidence = session.Evidence(decision.Actor);
            var links = new List<LabLink>();
            foreach (var key in decision.Action.Gate.Inputs.Concat(decision.Action.Recognition.Inputs).Distinct())
            {
                if (!writes.TryGetValue(key, out var written) || written.Receipt.Actor == decision.Actor ||
                    !client.Knowledge.TryGetValue(key, out var fact) || !fact.Known || fact.Conflicted ||
                    fact.Value.GetRawText() != written.Fact.Value.GetRawText()) continue;
                var source = evidence.LastOrDefault(e => e.Key == key && e.Value.GetRawText() == written.Fact.Value.GetRawText() &&
                    e.Time == fact.ObservedAt && e.Time >= written.Receipt.Time / 60 && e.Time <= decision.StartedAt / 60 &&
                    (Num(Get(e.Source,"execution"),-1) == written.Receipt.Execution ||
                     Num(Get(e.Source,"world_revision"),-1) == written.Fact.Revision));
                if (source is not null)
                    links.Add(new(written.Receipt.Actor, written.Receipt.Action, written.Receipt.Time / 60, key, written.Fact.Value, source.Id));
            }
            var alternatives = (decision.Options ?? []).Where(option => option.PredictedReadiness == "True")
                .Select(option => option.Action).Distinct().Order(StringComparer.Ordinal).ToArray();
            pending[decision.Execution] = (decision.StartedAt / 60, alternatives, links.ToArray());
        }

        public void Record(ActionReceipt receipt, ActionOutcome? outcome)
        {
            var dispatched = pending.Remove(receipt.Execution, out var details);
            if (!receipt.Committed) return;
            if (dispatched) Actions.Add(new(receipt.Actor, receipt.Action, details.Start, receipt.Time / 60, details.Alternatives, details.Links));
            if (outcome is null) return;
            foreach (var change in outcome.Changes)
                if (change.After.Known && !change.After.Conflicted && change.After.Value.ValueKind != JsonValueKind.Undefined &&
                    (change.Before is not { Known: true, Conflicted: false } before || before.Value.GetRawText() != change.After.Value.GetRawText()))
                    writes[change.Key] = (receipt, change.After);
        }
    }

    static LabRun RunLab(CharacterSessionDefinition definition, string contentPath, double horizon, LabInput? input)
    {
        using var host = new NativeCli(JsonSerializer.SerializeToElement(new {content_path=contentPath, controller="ai", seed=1}),definition,horizon);
        host.lab = new();
        var state = host.session.SaveState();
        var slots = state.Scheduler.Slots;
        double? initial = null;
        if (input is not null)
        {
            slots = slots.Select(slot => slot.Actor == input.Actor ? slot with { Needs = slot.Needs with {
                Needs = slot.Needs.Needs.Select(need => {
                    if (need.Id != input.Need) return need;
                    initial = Math.Clamp(need.Value + input.Delta, 0, 100);
                    return need with { Value = initial.Value };
                }).ToArray() }} : slot).ToArray();
            if (initial is null) throw new InvalidDataException($"Unknown need: {input.Actor}/{input.Need}");
        }
        // The control and variants all use the same checkpoint restore path.
        host.session.RestoreState(state with { Scheduler = state.Scheduler with { Slots = slots }});
        while (host.Active) host.AdvanceCore(100);
        return new(input,initial,host.session.ContentTime,host.CampaignCompleted,host.failures,
            host.invariantFailures.Order(StringComparer.Ordinal).ToArray(),host.successfulActions,host.completed.Keys.Where(action => action.EndsWith(".join",StringComparison.Ordinal) ||
                action.EndsWith(".eat_supper",StringComparison.Ordinal)).Order(StringComparer.Ordinal).ToArray(),host.lab.Actions.ToArray());
    }

    static LabScore ScoreLab(LabRun baseline, LabRun variant)
    {
        var responses = new List<LabResponse>();
        var changedPeers = 0;
        foreach (var group in variant.Actions.Where(a => a.Actor != variant.Input!.Actor).GroupBy(a => a.Actor))
        {
            var prior = baseline.Actions.Where(a => a.Actor == group.Key).OrderBy(a => a.Start).ToArray();
            var after = group.OrderBy(a => a.Start).ToArray();
            var i = 0;
            while (i < Math.Min(prior.Length, after.Length) && prior[i].Action == after[i].Action) i++;
            if (i == Math.Min(prior.Length, after.Length)) continue; // Timing changes, missing suffixes and repetition alone earn no points.
            changedPeers++;
            var links = after[i].Observed.Where(link =>
                !prior[i].Observed.Any(other => other.Actor == link.Actor && other.Action == link.Action && other.Fact == link.Fact &&
                    other.Value.GetRawText() == link.Value.GetRawText()) &&
                // A newly selected upstream action, or an earlier handoff the baseline receiver did not have yet.
                !baseline.Actions.Any(a => a.Actor == link.Actor && a.Action == link.Action && a.End <= prior[i].Start)).ToArray();
            if (links.Length > 0) responses.Add(new(prior[i], after[i], links));
        }
        return new(responses.ToArray(), changedPeers);
    }

    public static int CompareEmergence(string[] args)
    {
        if (args.Length is < 1 or > 4 || (args.Length > 1 && (!double.TryParse(args[1],NumberStyles.Float,CultureInfo.InvariantCulture,out var until) || !double.IsFinite(until))) ||
            (args.Length > 2 && (!int.TryParse(args[2],out var parsed) || parsed is < 1 or > 96)))
        {
            Console.Error.WriteLine("Usage: --compare-emergence REPORT.json [end_game_minute=1440] [variants=32] [content.dv]");
            return 2;
        }
        try
        {
            var timer = Stopwatch.StartNew();
            var horizon = args.Length > 1 ? double.Parse(args[1],CultureInfo.InvariantCulture) : 1440;
            var limit = args.Length > 2 ? int.Parse(args[2],CultureInfo.InvariantCulture) : 32;
            var contentPath = args.Length > 3 ? args[3] : DefaultContent;
            var definition = new CharacterSessionDefinition(File.ReadAllText(PathOf(contentPath)),File.ReadAllText("assets/data/98-runtime-session.data.dv"));
            var candidates = definition.Create().SaveState().Scheduler.Slots.Where(slot => slot.Autonomous && slot.Actor != "demon").ToArray();
            var inputs = (from need in new[]{"energy","social","thirst","hunger","comfort","hygiene"}
                from delta in new double[]{-25,25}
                from slot in candidates
                where slot.Needs.Needs.Any(n => n.Id == need && Math.Clamp(n.Value+delta,0,100) != n.Value)
                select new LabInput(slot.Actor,need,delta)).Take(limit).ToArray();
            if (inputs.Length == 0) throw new InvalidDataException("Scenario has no editable autonomous actor needs.");
            var baseline = RunLab(definition,contentPath,horizon,null);
            var repeat = RunLab(definition,contentPath,horizon,null);
            var repeatable = Encode(baseline) == Encode(repeat);
            var requiredCompletion = baseline.CampaignCompleted;
            var workers = Math.Min(4, Math.Max(1, Environment.ProcessorCount / 2));
            var finished = 0;
            Console.Error.WriteLine($"Control repeated: {repeatable}; running {inputs.Length} variants across {workers} workers.");
            var rows = inputs.AsParallel().AsOrdered().WithDegreeOfParallelism(workers).Select(input => {
                var run = RunLab(definition,contentPath,horizon,input);
                var score=ScoreLab(baseline,run);
                var count=Interlocked.Increment(ref finished);
                if (count % 4 == 0 || count == inputs.Length) Console.Error.WriteLine($"Compared {count}/{inputs.Length} variants.");
                return new { run, score, eligible=repeatable && baseline.UnexpectedFailures==0 && baseline.InvariantFailures.Length==0 &&
                    run.UnexpectedFailures==0 && run.InvariantFailures.Length==0 && (!requiredCompletion || run.CampaignCompleted) && (run.CampaignCompleted || run.GameTime+1e-6>=baseline.GameTime) && baseline.Milestones.Except(run.Milestones).Count()==0 };
            }).ToArray();
            var best = rows.Where(row => row.eligible && row.score.Responses.Length > 0)
                .OrderByDescending(row => row.score.Responses.Length)
                .ThenBy(row => row.run.Input!.Actor,StringComparer.Ordinal).ThenBy(row => row.run.Input!.Need,StringComparer.Ordinal)
                .ThenBy(row => row.run.Input!.Delta).FirstOrDefault();
            var bestRepeatable = best is not null && Encode(best.run) == Encode(RunLab(definition,contentPath,horizon,best.run.Input));
            var output = PathOf(args[0]);
            Directory.CreateDirectory(Path.GetDirectoryName(output)!);
            File.WriteAllText(output,JsonSerializer.Serialize(new {schema="dv-causal-batch-v1",content=contentPath,content_hash=definition.Hash,
                requested_end_game_minute=horizon, elapsed_seconds=timer.Elapsed.TotalSeconds,baseline_repeatable=repeatable,best_repeatable=bestRepeatable,baseline,best,variants=rows},
                new JsonSerializerOptions(Json){WriteIndented=true}));
            Console.WriteLine($"{rows.Length+(best is null?2:3)} runs in {timer.Elapsed.TotalSeconds:F1}s; baseline_repeatable={repeatable}; eligible={rows.Count(row=>row.eligible)}; best={best?.run.Input}; provenanced_responses={best?.score.Responses.Length??0}; report={output}");
            return repeatable && (best is null || bestRepeatable) ? 0 : 1;
        }
        catch (Exception e) { Console.Error.WriteLine(e); return 2; }
    }
}
