using System.Diagnostics;
using System.Runtime.ExceptionServices;
using System.Security.Cryptography;
using System.Text.Json;

namespace DuelView.Core;

public enum CaseWorkStatus { Running, Completed, Cancelled, BudgetExhausted, Faulted }

/// <summary>Computation telemetry only; elapsed time never advances the game clock.</summary>
public sealed record CaseWorkSlice(CaseWorkStatus Status, int Operations, long TotalOperations,
    TimeSpan Elapsed, string Phase, string? Error);

/// <summary>A single-owner, resumable computation. A deadline is a Stopwatch timestamp,
/// not a game time or UTC date. Deadlines are cooperative between atomic operations.</summary>
public abstract class CaseWork<T> : IDisposable where T : class
{
    private IEnumerator<int>? cursor;
    private T? result;
    private ExceptionDispatchInfo? failure;
    public CaseWorkStatus Status { get; private set; } = CaseWorkStatus.Running;
    public long TotalOperations { get; private set; }
    public TimeSpan TotalElapsed { get; private set; }
    public string Phase { get; protected set; } = "created";
    public string? Error => failure?.SourceException.Message;
    public T Result => Status == CaseWorkStatus.Completed ? result! : throw new InvalidOperationException("Computation has no completed result: " + Status);
    protected abstract IEnumerable<int> Execute();
    protected void Finish(T value) => result = value;

    public CaseWorkSlice Advance(int maxOperations, TimeSpan timeBudget, CancellationToken cancellationToken = default)
    {
        if (timeBudget < TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(timeBudget));
        var now = Stopwatch.GetTimestamp();
        var ticks = timeBudget.TotalSeconds * Stopwatch.Frequency;
        var deadline = ticks >= long.MaxValue - now ? long.MaxValue : now + (long)ticks;
        return AdvanceUntil(maxOperations, deadline, cancellationToken);
    }

    public CaseWorkSlice AdvanceUntil(int maxOperations, long deadlineTimestamp, CancellationToken cancellationToken = default)
    {
        if (maxOperations < 1) throw new ArgumentOutOfRangeException(nameof(maxOperations));
        var started = Stopwatch.GetTimestamp();
        var operations = 0;
        try
        {
            if (Status == CaseWorkStatus.Running && cancellationToken.IsCancellationRequested) Cancel();
            while (Status == CaseWorkStatus.Running && operations < maxOperations && Stopwatch.GetTimestamp() < deadlineTimestamp)
            {
                if (cancellationToken.IsCancellationRequested) { Cancel(); break; }
                cursor ??= Execute().GetEnumerator();
                var more = cursor.MoveNext();
                operations++;
                TotalOperations++;
                if (!more)
                {
                    if (result is null) throw new InvalidOperationException("Computation ended without a result.");
                    Status = CaseWorkStatus.Completed;
                    cursor.Dispose();
                    cursor = null;
                }
            }
        }
        catch (Exception error)
        {
            result = null;
            failure = ExceptionDispatchInfo.Capture(error);
            Status = error is CaseWorkBudgetException ? CaseWorkStatus.BudgetExhausted : CaseWorkStatus.Faulted;
            cursor?.Dispose();
            cursor = null;
        }
        var elapsed = Stopwatch.GetElapsedTime(started);
        TotalElapsed += elapsed;
        return new(Status, operations, TotalOperations, elapsed, Phase, Error);
    }

    public T RunToCompletion(CancellationToken cancellationToken = default)
    {
        while (Status == CaseWorkStatus.Running) AdvanceUntil(4096, long.MaxValue, cancellationToken);
        if (Status == CaseWorkStatus.Cancelled) throw new OperationCanceledException(cancellationToken);
        failure?.Throw();
        return Result;
    }

    public void Cancel()
    {
        if (Status != CaseWorkStatus.Running) return;
        result = null;
        Status = CaseWorkStatus.Cancelled;
        cursor?.Dispose();
        cursor = null;
    }
    public void Dispose() => Cancel();
}

internal sealed class CaseWorkBudgetException(string message) : InvalidOperationException(message);

/// <summary>The existing deterministic Horn inference, suspended inside premise matching.
/// The caller supplies an immutable scope and must not mutate its collections while work is active.
/// No partial proof is published; completion includes the independent proof checker.</summary>
public sealed class CaseInferenceWork : CaseWork<CaseProof>
{
    private readonly CaseScope scope;
    private readonly int maxNodes, maxMatches;
    public long Matches { get; private set; }
    public int NodeCount { get; private set; }

    public CaseInferenceWork(CaseScope scope, int maxNodes = 10000, int maxMatches = 1000000)
    {
        ArgumentNullException.ThrowIfNull(scope);
        if (maxNodes < 1 || maxNodes > 10000) throw new ArgumentOutOfRangeException(nameof(maxNodes), "Proof node limit must be within 1..10000");
        if (maxMatches < 1) throw new ArgumentOutOfRangeException(nameof(maxMatches));
        this.scope = scope;
        this.maxNodes = maxNodes;
        this.maxMatches = maxMatches;
    }

    protected override IEnumerable<int> Execute()
    {
        Phase = "validate-theory";
        CaseCheckResult? theoryCheck = null;
        foreach (var step in CaseProofChecker.ValidateTheorySteps(scope, result => theoryCheck = result)) yield return step;
        if (!theoryCheck!.Valid) throw new ArgumentException(string.Join("; ", theoryCheck.Errors), nameof(scope));
        var facts = new Dictionary<string, CaseProofNode>(StringComparer.Ordinal);
        var steps = new List<CaseProofNode>();
        void Add(string kind, CaseLiteral literal, string reference, IReadOnlyList<string> parents, IReadOnlyDictionary<string, string> substitution)
        {
            if (facts.ContainsKey(literal.Key)) return;
            if (steps.Count >= maxNodes) throw new CaseWorkBudgetException("Case proof node budget exhausted; no completeness or uniqueness conclusion is available");
            var node = new CaseProofNode("p" + steps.Count, kind, literal, reference, parents, substitution);
            facts.Add(literal.Key, node);
            steps.Add(node);
            NodeCount = steps.Count;
        }
        void CountMatch()
        {
            if (++Matches > maxMatches) throw new CaseWorkBudgetException("Case match budget exhausted; no completeness or uniqueness conclusion is available");
        }
        Phase = "axioms";
        foreach (var axiom in scope.Axioms)
        {
            Add("axiom", axiom.Literal, axiom.Id, Array.Empty<string>(), new Dictionary<string, string>());
            yield return 0;
        }
        Phase = "match";
        bool changed;
        do
        {
            var before = steps.Count;
            foreach (var rule in scope.Rules)
            {
                // Freeze this rule's fact horizon, as the original array snapshot did.
                var availableCount = steps.Count;
                IEnumerable<int> Match(int index, Dictionary<string, string> substitution, List<string> parents)
                {
                    CountMatch();
                    yield return 0;
                    if (index == rule.Premises.Count)
                    {
                        Add("apply", rule.Conclusion.Substitute(substitution), rule.Id, parents.AsReadOnly(),
                            new System.Collections.ObjectModel.ReadOnlyDictionary<string, string>(substitution));
                        yield return 0;
                        yield break;
                    }
                    var required = rule.Premises[index];
                    for (var factIndex = 0; factIndex < availableCount; factIndex++)
                    {
                        var fact = steps[factIndex];
                        CountMatch();
                        yield return 0;
                        var actual = fact.Conclusion;
                        if (required.Predicate != actual.Predicate || required.Negative != actual.Negative || required.Args.Count != actual.Args.Count) continue;
                        var bindings = new Dictionary<string, string>(substitution, StringComparer.Ordinal);
                        var fits = true;
                        for (var i = 0; i < required.Args.Count; i++)
                        {
                            var term = required.Args[i]; var value = actual.Args[i];
                            if (term.StartsWith('?'))
                            { if (bindings.TryGetValue(term, out var old)) fits &= old == value; else bindings.Add(term, value); }
                            else fits &= term == value;
                            yield return 0;
                        }
                        if (fits)
                            foreach (var step in Match(index + 1, bindings, new List<string>(parents) { fact.Id })) yield return step;
                    }
                }
                foreach (var step in Match(0, new Dictionary<string, string>(StringComparer.Ordinal), new List<string>())) yield return step;
            }
            changed = before != steps.Count;
            yield return 0;
        } while (changed);
        Phase = "fingerprint";
        string? fingerprint = null;
        foreach (var step in CaseWorkFingerprint.Steps(scope, value => fingerprint = value)) yield return step;
        var proof = new CaseProof(scope.Id, steps.AsReadOnly(), fingerprint!);
        Phase = "check-proof";
        CaseCheckResult? check = null;
        foreach (var step in CaseProofChecker.CheckSteps(scope, proof, result => check = result)) yield return step;
        if (!check!.Valid) throw new InvalidOperationException("Generated proof rejected: " + string.Join("; ", check.Errors));
        Finish(proof);
    }
}

// Writes precisely the canonical { Id, Axioms, Rules } JSON used by CaseTheory.Fingerprint,
// but hashes each declaration as it is emitted instead of creating one large final buffer.
internal static class CaseWorkFingerprint
{
    internal static IEnumerable<int> Steps(CaseScope scope, Action<string> complete)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        using var sink = new HashStream(hash);
        using var writer = new Utf8JsonWriter(sink);
        writer.WriteStartObject();
        writer.WriteString("Id", scope.Id);
        writer.WriteStartArray("Axioms");
        foreach (var axiom in scope.Axioms)
        {
            JsonSerializer.Serialize(writer, axiom);
            writer.Flush();
            yield return 0;
        }
        writer.WriteEndArray();
        writer.WriteStartArray("Rules");
        foreach (var rule in scope.Rules)
        {
            JsonSerializer.Serialize(writer, rule);
            writer.Flush();
            yield return 0;
        }
        writer.WriteEndArray();
        writer.WriteEndObject();
        writer.Flush();
        complete(Convert.ToHexString(hash.GetHashAndReset()));
    }

    private sealed class HashStream(IncrementalHash hash) : Stream
    {
        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override void Write(byte[] buffer, int offset, int count) => hash.AppendData(buffer, offset, count);
        public override void Write(ReadOnlySpan<byte> buffer) => hash.AppendData(buffer);
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
    }
}
