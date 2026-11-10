using System.Globalization;
using System.Numerics;
using System.Text.Json;

namespace DuelView.Runtime;

internal static class Values
{
    internal static readonly JsonElement Empty = JsonSerializer.SerializeToElement(new { });
    internal static JsonElement Get(this JsonElement value, string key) =>
        value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var item) ? item : default;
    internal static string Text(this JsonElement value, string fallback = "") =>
        value.ValueKind == JsonValueKind.String ? value.GetString()! : fallback;
    internal static bool Flag(this JsonElement value, bool fallback = false) => value.ValueKind switch
    { JsonValueKind.True => true, JsonValueKind.False => false, _ => fallback };
    internal static IEnumerable<JsonElement> Items(this JsonElement value) =>
        value.ValueKind == JsonValueKind.Array ? value.EnumerateArray() : Enumerable.Empty<JsonElement>();
    internal static IEnumerable<JsonProperty> Fields(this JsonElement value) =>
        value.ValueKind == JsonValueKind.Object ? value.EnumerateObject() : Enumerable.Empty<JsonProperty>();
    internal static double Number(this JsonElement value, double fallback = 0) =>
        value.ValueKind == JsonValueKind.Number ? value.GetDouble() : ExactNumber.TryRead(value, out var number)
            ? (double)number.Numerator / (double)number.Denominator : fallback;
    internal static bool Same(JsonElement left, JsonElement right)
    {
        if (ExactNumber.TryRead(left, out var a) && ExactNumber.TryRead(right, out var b)) return a == b;
        if (left.ValueKind != right.ValueKind) return false;
        return left.ValueKind switch
        {
            JsonValueKind.String => left.GetString() == right.GetString(),
            JsonValueKind.True or JsonValueKind.False or JsonValueKind.Null or JsonValueKind.Undefined => true,
            JsonValueKind.Array => left.GetArrayLength() == right.GetArrayLength() && left.EnumerateArray().Zip(right.EnumerateArray()).All(p => Same(p.First, p.Second)),
            JsonValueKind.Object => left.EnumerateObject().Count() == right.EnumerateObject().Count() && left.EnumerateObject().All(p => right.TryGetProperty(p.Name, out var v) && Same(p.Value, v)),
            _ => false
        };
    }
}

internal readonly record struct ExactNumber
{
    internal BigInteger Numerator { get; }
    internal BigInteger Denominator { get; }
    internal ExactNumber(BigInteger numerator, BigInteger denominator)
    {
        if (denominator.IsZero) throw new InvalidDataException("Zero denominator in DV value.");
        var gcd = BigInteger.GreatestCommonDivisor(numerator, denominator) * denominator.Sign;
        Numerator = numerator / gcd; Denominator = denominator / gcd;
    }
    internal static bool TryRead(JsonElement value, out ExactNumber number)
    {
        string text;
        if (value.ValueKind == JsonValueKind.Number) text = value.GetRawText();
        else if (value.Get("$dv_rational").ValueKind == JsonValueKind.String) text = value.Get("$dv_rational").Text();
        else { number = default; return false; }
        var slash = text.IndexOf('/');
        if (slash >= 0)
        {
            number = new(BigInteger.Parse(text[..slash], CultureInfo.InvariantCulture), BigInteger.Parse(text[(slash + 1)..], CultureInfo.InvariantCulture));
            return true;
        }
        var exponentIndex = text.IndexOfAny(['e', 'E']);
        var exponent = exponentIndex < 0 ? 0 : int.Parse(text[(exponentIndex + 1)..], CultureInfo.InvariantCulture);
        if (Math.Abs((long)exponent) > 1000) throw new InvalidDataException("DV number exponent exceeds runtime budget.");
        if (exponentIndex >= 0) text = text[..exponentIndex];
        var dot = text.IndexOf('.');
        if (dot >= 0) { exponent -= text.Length - dot - 1; text = text.Remove(dot, 1); }
        var numerator = BigInteger.Parse(text, CultureInfo.InvariantCulture);
        number = exponent >= 0 ? new(numerator * BigInteger.Pow(10, exponent), BigInteger.One)
            : new(numerator, BigInteger.Pow(10, -exponent));
        return true;
    }
    internal int CompareTo(ExactNumber other) => (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator);
    internal ExactNumber Add(ExactNumber other) => new(Numerator * other.Denominator + other.Numerator * Denominator, Denominator * other.Denominator);
    internal JsonElement Json() => Denominator.IsOne && Numerator >= long.MinValue && Numerator <= long.MaxValue
        ? JsonSerializer.SerializeToElement((long)Numerator)
        : JsonSerializer.SerializeToElement(new Dictionary<string, string> { ["$dv_rational"] = $"{Numerator}/{Denominator}" });
}

public readonly record struct FieldKey(string Object, string Facet, string Field)
{
    internal static FieldKey Read(JsonElement reference, string subject)
    {
        var scope = reference.Get("subject").Text();
        if (scope.Length > 0 && scope != subject) throw new InvalidDataException("Cross-subject reference access.");
        if (reference.Get("type").Text() != "ref") throw new InvalidDataException("Expected DV field reference.");
        var key = new FieldKey(reference.Get("object").Text(), reference.Get("facet").Text(), reference.Get("field").Text());
        if (key.Object.Length == 0 || key.Facet.Length == 0 || key.Field.Length == 0)
            throw new InvalidDataException("Incomplete DV field reference.");
        return key;
    }
}

public sealed record Fact(JsonElement Value, bool Known, bool Conflicted, double Confidence, double ObservedAt, long Revision);
public sealed record FieldChange(FieldKey Key, Fact? Before, Fact After);
public sealed record SavedFact(FieldKey Key,Fact Fact);
public sealed record FactStoreState(string Subject,long Revision,SavedFact[] Facts);

/// <summary>One domain, one owner. A store never delegates missing reads to another domain.</summary>
public sealed class FactStore
{
    private readonly Dictionary<FieldKey, Fact> facts = [];
    public string Subject { get; }
    public long Revision { get; private set; }
    public FactStore(string subject) => Subject = subject;
    public Fact? Read(FieldKey key) => facts.GetValueOrDefault(key);
    public FactStoreState SaveState()=>new(Subject,Revision,facts.Select(pair=>new SavedFact(pair.Key,pair.Value)).ToArray());
    public void RestoreState(FactStoreState state)
    {
        if(state.Subject!=Subject || state.Revision<0 || state.Facts is null)throw new InvalidDataException("Invalid fact store checkpoint owner or revision.");
        var restored=new Dictionary<FieldKey,Fact>();
        foreach(var entry in state.Facts)
        {
            var key=entry.Key;var value=entry.Fact;
            if(string.IsNullOrWhiteSpace(key.Object)||string.IsNullOrWhiteSpace(key.Facet)||string.IsNullOrWhiteSpace(key.Field)||
               value is null || value.Value.ValueKind==JsonValueKind.Undefined || value.Revision<0 || value.Revision>state.Revision ||
               !double.IsFinite(value.Confidence)||value.Confidence is <0 or >1 || !double.IsFinite(value.ObservedAt) || value.ObservedAt<0 || !restored.TryAdd(key,value))
                throw new InvalidDataException("Invalid fact store checkpoint entry.");
        }
        facts.Clear();foreach(var item in restored)facts.Add(item.Key,item.Value);Revision=state.Revision;
    }
    internal IEnumerable<KeyValuePair<FieldKey, Fact>> Entries => facts;
    internal void Initialize(JsonElement objects)
    {
        foreach (var obj in objects.Fields())
            foreach (var facet in obj.Value.Get("facets").Fields())
                foreach (var field in facet.Value.Fields())
                {
                    var cell = field.Value;
                    facts.Add(new(obj.Name, facet.Name, field.Name), new(cell.Get("value"), cell.Get("known").Flag(),
                        cell.Get("conflicted").Flag(), cell.Get("confidence").Number(), cell.Get("time").Number(), 0));
                }
    }
    internal IReadOnlyList<FieldChange> Apply(IReadOnlyDictionary<FieldKey, Fact> writes)
    {
        var changes = new List<FieldChange>();
        foreach (var (key, value) in writes)
        {
            var before = Read(key);
            if (before is not null && before.Known == value.Known && before.Conflicted == value.Conflicted &&
                before.Confidence == value.Confidence && Values.Same(before.Value, value.Value)) continue;
            changes.Add(new(key, before, value with { Revision = Revision + 1 }));
        }
        if (changes.Count == 0) return changes;
        Revision++;
        foreach (var change in changes) facts[change.Key] = change.After;
        return changes;
    }
}
