using System.Text.Json;

namespace DuelView.Runtime;

public enum Truth { Unknown, False, True }

/// <summary>Compiled read dependencies and evaluation. Unknown information stays unknown.</summary>
public abstract record Condition
{
    public abstract Truth Evaluate(Func<FieldKey, Fact?> read);
    public abstract IEnumerable<FieldKey> Inputs { get; }
    public virtual IEnumerable<double> ClockThresholds(FieldKey clock) => [];
    public virtual IEnumerable<double> WakeTimes(Func<FieldKey, Fact?> read, FieldKey clock) => ClockThresholds(clock);
    public static Condition Compile(JsonElement value, string subject)
    {
        return value.Get("op").Text() switch
        {
            "constant" => new Constant(value.Get("value").ValueKind switch
            { JsonValueKind.True => Truth.True, JsonValueKind.False => Truth.False,
                _ => value.Get("value").Text() switch { "true" => Truth.True, "false" => Truth.False, _ => Truth.Unknown } }),
            "equals" => new EqualsValue(FieldKey.Read(value.Get("ref"), subject), value.Get("value")),
            "known" => new KnownValue(FieldKey.Read(value.Get("ref"), subject)),
            "at_least" => new AtLeast(FieldKey.Read(value.Get("ref"), subject), value.Get("value")),
            "not" => new Negate(Compile(value.Get("item"), subject)),
            "all" => new All(value.Get("items").Items().Select(v => Compile(v, subject)).ToArray()),
            "held_for" => new HeldFor(FieldKey.Read(value.Get("ref"), subject), value.Get("value"),
                FieldKey.Read(value.Get("clock"), subject), value.Get("duration").Number()),
            _ => throw new InvalidDataException("Unsupported DV condition: " + value.GetRawText())
        };
    }
    public sealed record Constant(Truth Value) : Condition
    {
        public override Truth Evaluate(Func<FieldKey, Fact?> read) => Value;
        public override IEnumerable<FieldKey> Inputs => [];
    }
    public sealed record KnownValue(FieldKey Key) : Condition
    {
        public override Truth Evaluate(Func<FieldKey, Fact?> read) => read(Key) is { Known: true, Conflicted: false } ? Truth.True : Truth.False;
        public override IEnumerable<FieldKey> Inputs => [Key];
    }
    public sealed record EqualsValue(FieldKey Key, JsonElement Value) : Condition
    {
        public override Truth Evaluate(Func<FieldKey, Fact?> read) => read(Key) is { Known: true, Conflicted: false } fact
            ? Values.Same(fact.Value, Value) ? Truth.True : Truth.False : Truth.Unknown;
        public override IEnumerable<FieldKey> Inputs => [Key];
    }
    public sealed record AtLeast(FieldKey Key, JsonElement Value) : Condition
    {
        public override Truth Evaluate(Func<FieldKey, Fact?> read) => read(Key) is { Known: true, Conflicted: false } fact &&
            ExactNumber.TryRead(fact.Value, out var a) && ExactNumber.TryRead(Value, out var b)
            ? a.CompareTo(b) >= 0 ? Truth.True : Truth.False : Truth.Unknown;
        public override IEnumerable<FieldKey> Inputs => [Key];
        public override IEnumerable<double> ClockThresholds(FieldKey clock) => Key == clock && Value.ValueKind == JsonValueKind.Number ? [Value.GetDouble()] : [];
    }
    public sealed record Negate(Condition Item) : Condition
    {
        public override Truth Evaluate(Func<FieldKey, Fact?> read) => Item.Evaluate(read) switch { Truth.True => Truth.False, Truth.False => Truth.True, _ => Truth.Unknown };
        public override IEnumerable<FieldKey> Inputs => Item.Inputs;
        public override IEnumerable<double> ClockThresholds(FieldKey clock) => Item.ClockThresholds(clock);
        public override IEnumerable<double> WakeTimes(Func<FieldKey, Fact?> read, FieldKey clock) => Item.WakeTimes(read, clock);
    }
    public sealed record All(IReadOnlyList<Condition> Items) : Condition
    {
        public override Truth Evaluate(Func<FieldKey, Fact?> read)
        {
            var unknown = false;
            foreach (var item in Items)
            {
                var value = item.Evaluate(read);
                if (value == Truth.False) return Truth.False;
                unknown |= value == Truth.Unknown;
            }
            return unknown ? Truth.Unknown : Truth.True;
        }
        public override IEnumerable<FieldKey> Inputs => Items.SelectMany(x => x.Inputs).Distinct();
        public override IEnumerable<double> ClockThresholds(FieldKey clock) => Items.SelectMany(x => x.ClockThresholds(clock));
        public override IEnumerable<double> WakeTimes(Func<FieldKey, Fact?> read, FieldKey clock) => Items.SelectMany(x => x.WakeTimes(read, clock));
    }
    public sealed record HeldFor(FieldKey Key, JsonElement Value, FieldKey Clock, double Duration) : Condition
    {
        public override Truth Evaluate(Func<FieldKey, Fact?> read)
        {
            if (read(Key) is not { Known: true, Conflicted: false } fact || read(Clock) is not { Known: true, Conflicted: false } now) return Truth.Unknown;
            if (!Values.Same(fact.Value, Value)) return Truth.False;
            return now.Value.Number() >= fact.ObservedAt + Duration ? Truth.True : Truth.False;
        }
        public override IEnumerable<FieldKey> Inputs => [Key, Clock];
        public override IEnumerable<double> WakeTimes(Func<FieldKey, Fact?> read, FieldKey clock) => Clock == clock &&
            read(Key) is { Known: true, Conflicted: false } fact && Values.Same(fact.Value, Value)
            ? [fact.ObservedAt + Duration] : [];
    }
}

internal sealed record Effect(FieldKey Key, JsonElement Value, bool Increment)
{
    internal static Effect Compile(JsonElement value, string subject) => new(FieldKey.Read(value.Get("ref"), subject),
        value.Get("value"), value.Get("op").Text() switch
        { "assign" => false, "increment" => true, _ => throw new InvalidDataException("Unsupported DV effect.") });
    internal Fact Resolve(Func<FieldKey, Fact?> read, double time, double confidence = 1)
    {
        var result = Value;
        if (Increment)
        {
            var before = read(Key);
            if (before is not { Known: true, Conflicted: false } || !ExactNumber.TryRead(before.Value, out var a) || !ExactNumber.TryRead(Value, out var b))
                throw new InvalidOperationException("Increment needs a known uncontested number: " + Key);
            result = a.Add(b).Json();
        }
        return new(result, true, false, confidence, time, 0);
    }
}

internal sealed record Rule(string Id, Condition Premise, IReadOnlyList<Effect> Effects, Condition? Postcondition, string Mode, double Confidence, JsonElement Basis)
{
    internal static Rule Compile(string id, JsonElement adoption, string subject)
    {
        var law = adoption.Get("law");
        return new(id, Condition.Compile(law.Get("premise"), subject), law.Get("effects").Items().Select(v => Effect.Compile(v, subject)).ToArray(),
            law.Get("postcondition").ValueKind == JsonValueKind.Object ? Condition.Compile(law.Get("postcondition"), subject) : null,
            adoption.Get("mode").Text(), adoption.Get("confidence").Number(1), adoption.Get("basis"));
    }
    internal Dictionary<FieldKey, Fact> Preview(Func<FieldKey, Fact?> read, double time)
    {
        var writes = new Dictionary<FieldKey, Fact>();
        Fact? Read(FieldKey key) => writes.GetValueOrDefault(key) ?? read(key);
        foreach (var effect in Effects) writes[effect.Key] = effect.Resolve(Read, time, Confidence);
        if (Postcondition is not null && Postcondition.Evaluate(Read) != Truth.True)
            throw new InvalidOperationException("DV postcondition failed: " + Id);
        return writes;
    }
}
