namespace DuelView.Core;

/// <summary>Travel time estimates from supplied navigation data; no world state is changed.</summary>
public static class CaseTravel
{
    public enum Mode { MetricPath, RoomGraphSeconds }
    public enum Access { Open, Unknown, Locked }
    public enum Status { Estimated, Unknown, Locked, Unreachable }

    // Directed edge. Bounds are metres in MetricPath mode and seconds in RoomGraphSeconds mode.
    public sealed record Edge(string From, string To, double Lower, double Upper, Access Access, string Source);
    public sealed record PathEstimate(double Seconds, IReadOnlyList<string> Nodes, IReadOnlyList<string> Sources);
    public sealed record Result(Mode Mode, Status Status, PathEstimate? Lower, PathEstimate? Upper, bool UnknownAlternative = false);
    public sealed record Point3(double X, double Y, double Z);

    /// <summary>Estimate from a host-supplied navigation polyline in metres, without claiming it was traversed.</summary>
    public static Result FromNavigationPath(IEnumerable<Point3> points, double minimumSpeed, double maximumSpeed, string source)
    {
        ArgumentNullException.ThrowIfNull(points);
        ArgumentException.ThrowIfNullOrWhiteSpace(source);
        if (!double.IsFinite(minimumSpeed) || !double.IsFinite(maximumSpeed) || minimumSpeed <= 0 || maximumSpeed < minimumSpeed)
            throw new ArgumentException("Finite positive ordered speed bounds are required.");
        var path = points.ToArray();
        if (path.Length == 0) throw new ArgumentException("Navigation path must contain a point.");
        if (path.Any(p => p is null || !double.IsFinite(p.X) || !double.IsFinite(p.Y) || !double.IsFinite(p.Z)))
            throw new ArgumentException("Navigation points must have finite coordinates.");
        double length = 0;
        for (var i = 1; i < path.Length; i++)
        {
            var dx = path[i].X - path[i - 1].X; var dy = path[i].Y - path[i - 1].Y; var dz = path[i].Z - path[i - 1].Z;
            length += double.Hypot(double.Hypot(dx, dy), dz);
            if (!double.IsFinite(length)) throw new OverflowException("Navigation path exceeds finite range.");
        }
        var lower = length / maximumSpeed; var upper = length / minimumSpeed;
        if (!double.IsFinite(lower) || !double.IsFinite(upper)) throw new OverflowException("Travel estimate exceeds finite range.");
        var nodes = Enumerable.Range(0, path.Length).Select(i => i.ToString(System.Globalization.CultureInfo.InvariantCulture)).ToArray();
        var sources = Enumerable.Repeat(source, path.Length - 1).ToArray();
        return new(Mode.MetricPath, Status.Estimated, new(lower, nodes, sources), new(upper, nodes, sources));
    }

    /// <summary>
    /// Bounds estimate the fastest route in the open subgraph, not all possible routes, observations or guarantees.
    /// Metric speed bounds are metres per second and strictly positive. The caller supplies all known nodes.
    /// </summary>
    public static Result Estimate(Mode mode, string origin, string target, IEnumerable<string> knownNodes,
        IEnumerable<Edge> edges, double? minimumSpeed = null, double? maximumSpeed = null)
    {
        if (!Enum.IsDefined(mode)) throw new ArgumentOutOfRangeException(nameof(mode));
        ArgumentException.ThrowIfNullOrWhiteSpace(origin);
        ArgumentException.ThrowIfNullOrWhiteSpace(target);
        ArgumentNullException.ThrowIfNull(knownNodes);
        ArgumentNullException.ThrowIfNull(edges);
        if (mode == Mode.MetricPath)
        {
            if (minimumSpeed is null || maximumSpeed is null || !double.IsFinite(minimumSpeed.Value) ||
                !double.IsFinite(maximumSpeed.Value) || minimumSpeed <= 0 || maximumSpeed < minimumSpeed)
                throw new ArgumentException("Metric mode requires finite positive ordered speed bounds.");
        }
        else if (minimumSpeed is not null || maximumSpeed is not null)
            throw new ArgumentException("Room graph mode does not accept speeds.");

        var nodes = new HashSet<string>(StringComparer.Ordinal);
        foreach (var node in knownNodes)
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(node);
            nodes.Add(node);
        }
        var graph = new Dictionary<string, List<Edge>>(StringComparer.Ordinal);
        foreach (var edge in edges)
        {
            ArgumentNullException.ThrowIfNull(edge);
            ArgumentException.ThrowIfNullOrWhiteSpace(edge.From);
            ArgumentException.ThrowIfNullOrWhiteSpace(edge.To);
            ArgumentException.ThrowIfNullOrWhiteSpace(edge.Source);
            if (!nodes.Contains(edge.From) || !nodes.Contains(edge.To))
                throw new ArgumentException("Every edge endpoint must be a known node.");
            if (!Enum.IsDefined(edge.Access) || !double.IsFinite(edge.Lower) || !double.IsFinite(edge.Upper) ||
                edge.Lower < 0 || edge.Upper < edge.Lower)
                throw new ArgumentException("Edge access and finite nonnegative ordered bounds are required.");
            if (!graph.TryGetValue(edge.From, out var outgoing)) graph[edge.From] = outgoing = new List<Edge>();
            outgoing.Add(edge);
        }
        if (!nodes.Contains(origin) || !nodes.Contains(target)) return new(mode, Status.Unknown, null, null);
        var low = Shortest(origin, target, graph, e => e.Access == Access.Open, false);
        if (low is null)
        {
            if (Shortest(origin, target, graph, e => e.Access != Access.Locked, false) is not null)
                return new(mode, Status.Unknown, null, null);
            if (Shortest(origin, target, graph, _ => true, false) is not null)
                return new(mode, Status.Locked, null, null);
            return new(mode, Status.Unreachable, null, null);
        }
        var high = Shortest(origin, target, graph, e => e.Access == Access.Open, true)!;
        double lower = mode == Mode.MetricPath ? low.Seconds / maximumSpeed!.Value : low.Seconds;
        double upper = mode == Mode.MetricPath ? high.Seconds / minimumSpeed!.Value : high.Seconds;
        if (!double.IsFinite(lower) || !double.IsFinite(upper)) throw new OverflowException("Travel estimate exceeds finite range.");
        return new(mode, Status.Estimated, low with { Seconds = lower }, high with { Seconds = upper },
            HasUnknownAlternative(origin, target, graph));
    }

    private static bool HasUnknownAlternative(string origin, string target, Dictionary<string, List<Edge>> graph)
    {
        var visited = new HashSet<(string Node, bool Unknown)> { (origin, false) };
        var queue = new Queue<(string Node, bool Unknown)>(); queue.Enqueue((origin, false));
        while (queue.TryDequeue(out var item))
        {
            if (item.Node == target && item.Unknown) return true;
            if (!graph.TryGetValue(item.Node, out var outgoing)) continue;
            foreach (var edge in outgoing)
            {
                if (edge.Access == Access.Locked) continue;
                var next = (edge.To, item.Unknown || edge.Access == Access.Unknown);
                if (visited.Add(next)) queue.Enqueue(next);
            }
        }
        return false;
    }

    private static PathEstimate? Shortest(string origin, string target, Dictionary<string, List<Edge>> graph,
        Func<Edge, bool> allowed, bool upper)
    {
        var distances = new Dictionary<string, double>(StringComparer.Ordinal) { [origin] = 0 };
        var previous = new Dictionary<string, Edge>(StringComparer.Ordinal);
        var queue = new PriorityQueue<string, double>();
        queue.Enqueue(origin, 0);
        while (queue.TryDequeue(out var node, out var distance))
        {
            if (distance > distances[node]) continue;
            if (node == target)
            {
                var path = new List<string> { node };
                var sources = new List<string>();
                while (previous.TryGetValue(node, out var edge))
                {
                    sources.Add(edge.Source);
                    node = edge.From;
                    path.Add(node);
                }
                path.Reverse(); sources.Reverse();
                return new(distance, path, sources);
            }
            if (!graph.TryGetValue(node, out var outgoing)) continue;
            foreach (var edge in outgoing)
            {
                if (!allowed(edge)) continue;
                var candidate = distance + (upper ? edge.Upper : edge.Lower);
                if (!double.IsFinite(candidate)) throw new OverflowException("Travel path exceeds finite range.");
                if (distances.TryGetValue(edge.To, out var old) && candidate >= old) continue;
                distances[edge.To] = candidate;
                previous[edge.To] = edge;
                queue.Enqueue(edge.To, candidate);
            }
        }
        return null;
    }
}
