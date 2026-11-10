namespace DuelView.Runtime;

public enum RoomPhase { Unloaded, Preparing, Active, CoolingDown, Unloading }
public enum RoomEffect { None, Prepare, Activate, Retain, Release }
public readonly record struct RoomTransition(RoomPhase Before, RoomPhase After, RoomEffect Effect, long Generation);

/// <summary>Presentation residency only. World metadata and simulation remain owned by the session.</summary>
public sealed class RoomLifecycle
{
    public RoomPhase Phase { get; private set; }
    public long Generation { get; private set; }
    public double LastDemandAt { get; private set; }
    public bool Prepared { get; private set; }
    private double lastNow = double.NegativeInfinity;
    private bool activeDemand;

    public RoomTransition Update(double now, bool prepare, bool active, bool protectedInFlight, double retentionSeconds)
    {
        if (!double.IsFinite(now) || now < lastNow) throw new ArgumentOutOfRangeException(nameof(now));
        if (!double.IsFinite(retentionSeconds) || retentionSeconds < 0) throw new ArgumentOutOfRangeException(nameof(retentionSeconds));
        lastNow = now;
        activeDemand = active;
        var before = Phase;
        var effect = RoomEffect.None;
        if (prepare || active || protectedInFlight) LastDemandAt = now;
        switch (Phase)
        {
            case RoomPhase.Unloaded when prepare || active || protectedInFlight:
                Generation++;
                Phase = RoomPhase.Preparing;
                effect = RoomEffect.Prepare;
                break;
            case RoomPhase.Preparing:
                if (!prepare && !active && !protectedInFlight && now - LastDemandAt >= retentionSeconds)
                { Generation++; Phase = RoomPhase.Unloading; effect = RoomEffect.Release; }
                else if (Prepared && active)
                { Phase = RoomPhase.Active; effect = RoomEffect.Activate; }
                break;
            case RoomPhase.Active when !active:
                Phase = RoomPhase.CoolingDown;
                effect = RoomEffect.Retain;
                break;
            case RoomPhase.CoolingDown:
                if (active) { Phase = RoomPhase.Active; effect = RoomEffect.Activate; }
                else if (!prepare && !protectedInFlight && now - LastDemandAt >= retentionSeconds)
                { Generation++; Phase = RoomPhase.Unloading; effect = RoomEffect.Release; }
                break;
        }
        return new(before, Phase, effect, Generation);
    }

    // Async callbacks carry their generation. A cancelled request cannot publish a node.
    public RoomTransition CompletePreparation(long generation, bool? currentActiveDemand = null)
    {
        var before = Phase;
        if (generation != Generation || Phase != RoomPhase.Preparing || Prepared)
            return new(before, Phase, RoomEffect.None, Generation);
        if (currentActiveDemand.HasValue) activeDemand = currentActiveDemand.Value;
        Prepared = true;
        if (activeDemand) Phase = RoomPhase.Active;
        return new(before, Phase, activeDemand ? RoomEffect.Activate : RoomEffect.None, Generation);
    }

    public RoomTransition FailPreparation(long generation)
    {
        var before = Phase;
        if (generation != Generation || Phase != RoomPhase.Preparing || Prepared)
            return new(before, Phase, RoomEffect.None, Generation);
        Generation++;
        Phase = RoomPhase.Unloading;
        return new(before, Phase, RoomEffect.Release, Generation);
    }

    // Called after the host has removed the tree and released all resource references.
    public bool CompleteRelease(long generation)
    {
        if (generation != Generation || Phase != RoomPhase.Unloading) return false;
        Prepared = false;
        Phase = RoomPhase.Unloaded;
        return true;
    }
}
