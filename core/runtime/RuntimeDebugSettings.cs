using DuelView.Dv;

namespace DuelView.Runtime;

public sealed record RuntimeDebugSettings(double RoomInactiveRetentionSeconds)
{
    public static RuntimeDebugSettings Parse(string source)
    {
        var value=DvScriptReader.Parse(source).GetProperty("data").GetProperty("debug.coregodot").GetProperty("value");
        var seconds=value.GetProperty("room_inactive_retention_seconds").GetDouble();
        if (!double.IsFinite(seconds) || seconds<0) throw new InvalidDataException("Room retention must be a finite nonnegative number of seconds.");
        return new(seconds);
    }
}
