using System.Text.Json;

namespace DuelView.Runtime;

public sealed record RoomRequest(string Room, long Generation, bool Load, RoomEffect Effect = RoomEffect.None);
public sealed record RoomSimulation(string Room, double Distance, double Speed, string Mode);

/// <summary>Only presentation residency changes here. World facts and remembered maps
/// have independent lifetimes. Hosts acknowledge actual assembly and release.</summary>
public sealed class RoomResidency
{
    private sealed class Room(double distance, double speed)
    {
        internal double Distance = distance;
        internal double Speed = speed;
        internal readonly RoomLifecycle Lifecycle = new();
        internal bool Prepare;
        internal bool Visible;
        internal int Pins;
        internal double RetryAfter;
    }
    private readonly Dictionary<string, Room> rooms = new(StringComparer.Ordinal);
    private double retention;
    public double RetentionSeconds => retention;
    private readonly int requestsPerSlice;
    private readonly string inactiveMode;
    private readonly double retryDelay;
    private string[] order = [];
    private int cursor;

    public RoomResidency(JsonElement policy)
    {
        retention = policy.Get("inactive_retention_seconds").Number(double.NaN);
        var budget = policy.Get("room_requests_per_slice").Number(double.NaN);
        inactiveMode = policy.Get("inactive_simulation").Text();
        retryDelay = policy.Get("retry_delay_seconds").Number(double.NaN);
        if (!double.IsFinite(retryDelay) || retryDelay <= 0 || !double.IsFinite(retention) || retention < 0 || !double.IsFinite(budget) || budget < 1 || budget != Math.Truncate(budget) || budget > int.MaxValue || inactiveMode.Length == 0)
            throw new InvalidDataException("Invalid room residency policy.");
        requestsPerSlice = (int)budget;
    }

    public void Register(string id, double godotDistance, double godotSpeed)
    {
        if (id.Length == 0 || !double.IsFinite(godotDistance) || godotDistance < 0 || !double.IsFinite(godotSpeed) || godotSpeed <= 0)
            throw new InvalidDataException("Invalid Godot room simulation settings.");
        rooms.Add(id, new(godotDistance, godotSpeed));
        order = rooms.Keys.ToArray();
    }

    public void SetVisible(string id, bool visible, double now)
    {
        var room = rooms[id];
        if (!double.IsFinite(now) || now < 0) throw new ArgumentOutOfRangeException(nameof(now));
        room.Visible = visible;
    }

    public void SetPrepare(string id, bool prepare) => rooms[id].Prepare = prepare;
    public void SetRetentionSeconds(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds < 0) throw new ArgumentOutOfRangeException(nameof(seconds));
        retention = seconds;
    }
    public RoomPhase Phase(string id) => rooms[id].Lifecycle.Phase;

    // Pin all rooms along the next real route before a body starts crossing it.
    public void Pin(string id) => rooms[id].Pins++;
    public void Unpin(string id)
    {
        var room = rooms[id];
        if (room.Pins == 0) throw new InvalidOperationException("Room route pin is not held.");
        room.Pins--;
    }

    public IReadOnlyList<RoomRequest> Step(double now)
    {
        if (!double.IsFinite(now) || now < 0) throw new ArgumentOutOfRangeException(nameof(now));
        var requests = new List<RoomRequest>();
        // Both scanning and scene requests are spread across frames.
        for (var n = 0; n < Math.Min(order.Length, requestsPerSlice); n++)
        {
            var id = order[cursor];
            cursor = (cursor + 1) % order.Length;
            var room = rooms[id];
            if (now < room.RetryAfter) continue;
            var change = room.Lifecycle.Update(now, room.Prepare, room.Visible, room.Pins > 0, retention);
            if (change.Effect != RoomEffect.None)
                requests.Add(new(id, change.Generation, change.Effect == RoomEffect.Prepare, change.Effect));
        }
        return requests;
    }

    public RoomRequest? Acknowledge(RoomRequest request, bool success, double now)
    {
        if (!double.IsFinite(now) || now < 0) throw new ArgumentOutOfRangeException(nameof(now));
        var room = rooms[request.Room];
        var lifecycle = room.Lifecycle;
        if (lifecycle.Generation != request.Generation)
            throw new InvalidOperationException("Stale room assembly completion.");
        // Activation/retention are synchronous host effects. Loading and release have acknowledgements.
        if (request.Effect is RoomEffect.Activate or RoomEffect.Retain) return null;
        if (request.Load)
        {
            if (lifecycle.Phase != RoomPhase.Preparing || lifecycle.Prepared)
                throw new InvalidOperationException("Room is not waiting for preparation.");
            if (!success) throw new InvalidOperationException("Failed preparation requires CancelPreparation and actual release acknowledgement.");
            var change = lifecycle.CompletePreparation(request.Generation, room.Visible);
            if (change.Effect == RoomEffect.Activate)
                return new(request.Room, change.Generation, false, change.Effect);
        }
        else
        {
            if (!success) return request; // Host retries the same release; residency remains Unloading.
            if (!lifecycle.CompleteRelease(request.Generation))
                throw new InvalidOperationException("Room is not waiting for release.");
        }
        room.RetryAfter = Math.Max(room.RetryAfter, success ? now : now + retryDelay);
        return null;
    }

    public RoomRequest CancelPreparation(RoomRequest request, double now)
    {
        if (!double.IsFinite(now) || now < 0) throw new ArgumentOutOfRangeException(nameof(now));
        var room = rooms[request.Room];
        var change = room.Lifecycle.FailPreparation(request.Generation);
        if (change.Effect != RoomEffect.Release) throw new InvalidOperationException("Preparation cannot be cancelled.");
        room.RetryAfter = now + retryDelay;
        return new(request.Room, change.Generation, false, change.Effect);
    }

    public bool Ready(string id) => rooms[id].Lifecycle.Prepared && rooms[id].Lifecycle.Phase is RoomPhase.Active or RoomPhase.CoolingDown;
    public bool RouteReady(IEnumerable<string> path) => path.All(Ready);

    public RoomSimulation Simulation(string id, double corePathDistance)
    {
        if (!double.IsFinite(corePathDistance) || corePathDistance < 0) throw new ArgumentOutOfRangeException(nameof(corePathDistance));
        var room = rooms[id];
        return new(id, Ready(id) ? corePathDistance : room.Distance,
            room.Speed, Ready(id) ? "core_path_distance" : inactiveMode);
    }
}
