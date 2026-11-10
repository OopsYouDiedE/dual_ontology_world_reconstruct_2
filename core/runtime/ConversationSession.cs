using System.Text.Json;

namespace DuelView.Runtime;

public sealed record ConversationLine(string Speaker, string Label, string Text, double Duration);
public sealed record ConversationView(long Id, string Initiator, string Target, string Phase,
    int LineIndex, ConversationLine? Line, double? LineEndsAt);
public sealed record ConversationState(long Id,string Initiator,string Target,string Phase,int LineIndex,double? LineEndsAt);

/// <summary>Conversation state is owned by the session; the host only reports
/// physical alignment and requests advancement after the authored deadline.</summary>
public sealed class ConversationSession
{
    private readonly ConversationLine[] lines;
    public long Id { get; }
    public string Initiator { get; }
    public string Target { get; }
    public string Phase { get; private set; } = "approaching";
    public int LineIndex { get; private set; } = -1;
    public double? LineEndsAt { get; private set; }

    public ConversationSession(long id, string initiator, string target, JsonElement declaration)
    {
        if (id <= 0 || string.IsNullOrWhiteSpace(initiator) || string.IsNullOrWhiteSpace(target) || initiator == target)
            throw new InvalidDataException("Conversation requires two distinct participants.");
        Id = id; Initiator = initiator; Target = target;
        lines = declaration.Get("lines").Items().Select(line => new ConversationLine(
            line.Get("speaker").Text(), line.Get("label").Text(), line.Get("text").Text(), line.Get("duration_seconds").Number(double.NaN))).ToArray();
        if (lines.Length == 0 || lines.Any(line => (line.Speaker != initiator && line.Speaker != target) ||
            string.IsNullOrWhiteSpace(line.Label) || string.IsNullOrWhiteSpace(line.Text) || !double.IsFinite(line.Duration) || line.Duration <= 0))
            throw new InvalidDataException("Invalid conversation lines.");
    }

    public ConversationView View => new(Id, Initiator, Target, Phase, LineIndex,
        LineIndex >= 0 && LineIndex < lines.Length ? lines[LineIndex] : null, LineEndsAt);
    public ConversationState SaveState()=>new(Id,Initiator,Target,Phase,LineIndex,LineEndsAt);
    public static ConversationSession RestoreState(ConversationState state,JsonElement declaration)
    {
        var result=new ConversationSession(state.Id,state.Initiator,state.Target,declaration);
        var valid=state.Phase switch {
            "approaching"=>state.LineIndex==-1 && state.LineEndsAt is null,
            "speaking"=>state.LineIndex>=0 && state.LineIndex<result.lines.Length && state.LineEndsAt is { } end && double.IsFinite(end) && end>=0,
            "finished"=>state.LineIndex==result.lines.Length && state.LineEndsAt is null,
            "interrupted"=>state.LineIndex>=-1 && state.LineIndex<result.lines.Length && state.LineEndsAt is null,
            _=>false
        };
        if(!valid)throw new InvalidDataException("Invalid conversation checkpoint.");
        result.Phase=state.Phase;result.LineIndex=state.LineIndex;result.LineEndsAt=state.LineEndsAt;return result;
    }

    public bool Aligned(double now)
    {
        if (Phase != "approaching") return false;
        Phase = "speaking"; LineIndex = 0; LineEndsAt = now + lines[0].Duration;
        return true;
    }

    public bool Advance(int expectedLine, double now)
    {
        if (Phase != "speaking" || expectedLine != LineIndex || now < LineEndsAt) return false;
        if (++LineIndex == lines.Length) { Phase = "finished"; LineEndsAt = null; }
        else LineEndsAt = now + lines[LineIndex].Duration;
        return true;
    }

    public bool Interrupt()
    {
        if (Phase is "finished" or "interrupted") return false;
        Phase = "interrupted"; LineEndsAt = null; return true;
    }
}
