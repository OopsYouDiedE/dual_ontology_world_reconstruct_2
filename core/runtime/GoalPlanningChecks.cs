using System.Diagnostics;
using System.Text.Json;

namespace DuelView.Runtime;

public static class GoalPlanningChecks
{
    private static JsonElement J(object value) => JsonSerializer.SerializeToElement(value);
    private static FieldKey K(string name) => new("subject", "state", name);
    private static Fact F(object value) => new(J(value), true, false, 1, 0, 1);
    private static Condition Eq(string key, object value) => new Condition.EqualsValue(K(key), J(value));
    private static Condition All(params Condition[] items) => new Condition.All(items);
    private static Effect Set(string key, object value) => new(K(key), J(value), false);
    private static void Expect(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
    private static GoalPlanningRequest Request(Dictionary<FieldKey, Fact> known, GoalPlanningAction[] actions,
        GoalPlanningGoal[]? goals = null, HashSet<string>? first = null) => new(known,
        goals ?? [new("open", Eq("open", true), 30)], actions,
        first ?? actions.Select(a => a.Id).ToHashSet(StringComparer.Ordinal), MaxExpanded:128);

    public static int Run()
    {
        var failures = 0;
        void Check(string label, Action body)
        {
            var watch = Stopwatch.StartNew();
            try { body(); Console.WriteLine($"PASS {label} {watch.Elapsed.TotalMilliseconds:F3} ms"); }
            catch (Exception error) { ++failures; Console.WriteLine($"FAIL {label}: {error}"); }
        }
        foreach (var algorithm in new[] { "best_first", "beam" })
        {
            Check(algorithm + " plans a grounded three-step means-end chain without mutating knowledge", () =>
            {
                var known = new Dictionary<FieldKey, Fact> { [K("room")] = F("hall"), [K("key")] = F(false), [K("open")] = F(false) };
                var actions = new GoalPlanningAction[] {
                    new("walk", Eq("room", "hall"), [Set("room", "desk")], 1),
                    new("take_known_key", All(Eq("room", "desk"), Eq("key", false)), [Set("key", true)], 1),
                    new("unlock", Eq("key", true), [Set("open", true)], 1)
                };
                var result = GoalPlanning.Solve(Request(known, actions), algorithm);
                Expect(result.ActionSequence.SequenceEqual(new[] { "walk", "take_known_key", "unlock" }), "Expected the actual prerequisite chain.");
                Expect(result.ReachedGoals.Contains("open") && result.Utility == 27, "Incorrect goal utility.");
                Expect(known[K("room")].Value.GetString() == "hall" && !known[K("key")].Value.GetBoolean() && !known[K("open")].Value.GetBoolean(), "Planning wrote live knowledge.");
            });
            Check(algorithm + " cannot invent an unknown prerequisite or an unknown resource quantity", () =>
            {
                var known = new Dictionary<FieldKey, Fact> { [K("open")] = F(false) };
                var actions = new GoalPlanningAction[] {
                    new("unknown_key", Eq("key", true), [Set("open", true)], 1),
                    new("unmeasured_stock", new Condition.Constant(Truth.True), [new Effect(K("stock"), J(-1), true), Set("open", true)], 1)
                };
                Expect(GoalPlanning.Solve(Request(known, actions), algorithm).FirstAction is null, "Unknown facts were silently promoted to true.");
            });
            Check(algorithm + " failed attempts change the selected means and known changes permit replanning", () =>
            {
                var known = new Dictionary<FieldKey, Fact> { [K("open")] = F(false), [K("alternate")] = F(false) };
                var shortcut = new GoalPlanningAction("direct", Eq("open", false), [Set("open", true)], 1);
                var fallback = new GoalPlanningAction[] {
                    new("prepare", Eq("open", false), [Set("alternate", true)], 2),
                    new("alternative", Eq("alternate", true), [Set("open", true)], 2)
                };
                Expect(GoalPlanning.Solve(Request(known, [shortcut, .. fallback]), algorithm).FirstAction == "direct", "A first attempt was preemptively penalized.");
                Expect(GoalPlanning.Solve(Request(known, [shortcut with { FailurePenalty = 12 }, .. fallback]), algorithm).FirstAction == "prepare", "The failed attempt did not change the plan.");
                Expect(GoalPlanning.Solve(Request(known, [shortcut, .. fallback]), algorithm).FirstAction == "direct", "Removing a resolved obstruction did not restore the option.");
            });
            Check(algorithm + " retains uncertainty cost for another actor's consent", () =>
            {
                var known = new Dictionary<FieldKey, Fact> { [K("open")] = F(false), [K("alternate")] = F(false) };
                var actions = new GoalPlanningAction[] {
                    new("ask_unreliable_favor", Eq("open", false), [Set("open", true)], 1, UncertaintyCost:12),
                    new("prepare_own_tool", Eq("open", false), [Set("alternate", true)], 2),
                    new("use_own_tool", Eq("alternate", true), [Set("open", true)], 2)
                };
                Expect(GoalPlanning.Solve(Request(known, actions), algorithm).FirstAction == "prepare_own_tool", "Predicted consent was treated as free certainty.");
            });
            Check(algorithm + " preserves resource accounting between mutually competing goals", () =>
            {
                var known = new Dictionary<FieldKey, Fact> { [K("water")] = F(1), [K("food")] = F(false), [K("cloth")] = F(false) };
                var actions = new GoalPlanningAction[] {
                    new("cook", new Condition.AtLeast(K("water"), J(1)), [new(K("water"), J(-1), true), Set("food", true)], 1),
                    new("wash", new Condition.AtLeast(K("water"), J(1)), [new(K("water"), J(-1), true), Set("cloth", true)], 1)
                };
                var goals = new GoalPlanningGoal[] { new("food", Eq("food", true), 20), new("cloth", Eq("cloth", true), 30) };
                var result = GoalPlanning.Solve(Request(known, actions, goals), algorithm);
                Expect(result.FirstAction == "wash" && result.ReachedGoals.SequenceEqual(new[] { "cloth" }), "One unit of water was spent twice.");
            });
            Check(algorithm + " respects present first-step admission and does not reward already met goals", () =>
            {
                var known = new Dictionary<FieldKey, Fact> { [K("open")] = F(false), [K("prepared")] = F(false) };
                var actions = new GoalPlanningAction[] {
                    new("direct", new Condition.Constant(Truth.True), [Set("open", true)], 1),
                    new("prepare", new Condition.Constant(Truth.True), [Set("prepared", true)], 1),
                    new("finish", Eq("prepared", true), [Set("open", true)], 1)
                };
                var result = GoalPlanning.Solve(Request(known, actions, first:new HashSet<string>{"prepare"}), algorithm);
                Expect(result.FirstAction == "prepare", "A non-admitted action became the first move.");
                known[K("open")] = F(true);
                result = GoalPlanning.Solve(Request(known, actions), algorithm);
                Expect(result.FirstAction is null && result.Utility == 0, "An already satisfied purpose produced a spurious reward.");
            });
            Check(algorithm + " terminates at its explicit search budget", () =>
            {
                var known = new Dictionary<FieldKey, Fact> { [K("counter")] = F(0), [K("open")] = F(false) };
                var actions = new GoalPlanningAction[] {
                    new("count", new Condition.Constant(Truth.True), [new(K("counter"), J(1), true)], 0),
                    new("finish", new Condition.AtLeast(K("counter"), J(100)), [Set("open", true)], 1)
                };
                var result = GoalPlanning.Solve(Request(known, actions) with { MaxExpanded = 3 }, algorithm);
                Expect(result.Expanded <= 3 && result.FirstAction is null, "Bounded search escaped its budget or invented a completed goal.");
            });
        }
        return failures;
    }
}
