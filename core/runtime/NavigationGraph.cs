using System.Diagnostics;
using System.Text.Json;

namespace DuelView.Runtime;

public sealed record RouteNode(string Id, string Room);
public sealed record RouteEdge(string From, string To, double Meters, Condition Gate);
public sealed record RoutePlan(IReadOnlyList<RouteNode> Nodes, double Meters);

/// <summary>The logical graph lives for the session. Scene residency never deletes a
/// node, a door condition or an actor's journey. Search work is resumable.</summary>
public sealed class NavigationGraph
{
    private readonly Dictionary<string, RouteNode> nodes = new(StringComparer.Ordinal);
    private readonly Dictionary<string, List<RouteEdge>> edges = new(StringComparer.Ordinal);

    public NavigationGraph(JsonElement declaration)
    {
        foreach (var item in declaration.Get("nodes").Items())
        {
            var id = item.Get("id").Text();
            var room = item.Get("room").Text();
            if (id.Length == 0 || room.Length == 0) throw new InvalidDataException("Route node needs identity and room.");
            nodes.Add(id, new(id, room));
            edges.Add(id, []);
        }
        foreach (var item in declaration.Get("edges").Items())
        {
            var from = item.Get("from").Text();
            var to = item.Get("to").Text();
            var meters = item.Get("meters").Number(double.NaN);
            if (!nodes.ContainsKey(from) || !nodes.ContainsKey(to) || !double.IsFinite(meters) || meters <= 0)
                throw new InvalidDataException("Invalid route edge.");
            var gate = Condition.Compile(item.Get("gate"), "world");
            edges[from].Add(new(from, to, meters, gate));
            if (item.Get("bidirectional").Flag()) edges[to].Add(new(to, from, meters, gate));
        }
    }

    public RouteSearch Begin(string from, string to, Func<FieldKey, Fact?> read)
    {
        if (!nodes.ContainsKey(from) || !nodes.ContainsKey(to)) throw new InvalidOperationException("Unknown route endpoint.");
        return new(this, from, to, read);
    }

    public sealed class RouteSearch
    {
        private readonly NavigationGraph graph;
        private readonly string start, goal;
        private readonly Func<FieldKey, Fact?> read;
        private readonly PriorityQueue<string, double> frontier = new();
        private readonly Dictionary<string, double> distance = new(StringComparer.Ordinal);
        private readonly Dictionary<string, string> previous = new(StringComparer.Ordinal);
        private readonly HashSet<string> closed = new(StringComparer.Ordinal);
        private string? expanding;
        private int edgeCursor;
        private string? rebuilding;
        private readonly List<RouteNode> reverse = [];
        public bool Finished { get; private set; }
        public RoutePlan? Result { get; private set; }
        public long EdgeEvaluations { get; private set; }

        internal RouteSearch(NavigationGraph graph, string start, string goal, Func<FieldKey, Fact?> read)
        {
            this.graph = graph; this.start = start; this.goal = goal; this.read = read;
            frontier.Enqueue(start, 0); distance.Add(start, 0);
        }

        public void Step(int operationBudget, double milliseconds)
        {
            if (operationBudget <= 0 || !double.IsFinite(milliseconds) || milliseconds <= 0) throw new ArgumentOutOfRangeException(nameof(operationBudget));
            var timer = Stopwatch.StartNew();
            for (var count = 0; count < operationBudget && !Finished && timer.Elapsed.TotalMilliseconds < milliseconds; count++)
            {
                if (rebuilding is { } cursor)
                {
                    reverse.Add(graph.nodes[cursor]);
                    if (cursor == start)
                    {
                        reverse.Reverse();
                        Result = new(reverse.AsReadOnly(), distance[goal]);
                        Finished = true;
                    }
                    else rebuilding = previous[cursor];
                    continue;
                }
                if (expanding is null)
                {
                    if (!frontier.TryDequeue(out var next, out _)) { Finished = true; continue; }
                    if (!closed.Add(next)) continue;
                    if (next == goal) { rebuilding = goal; continue; }
                    expanding = next; edgeCursor = 0;
                }
                var adjacent = graph.edges[expanding];
                if (edgeCursor == adjacent.Count) { expanding = null; continue; }
                var edge = adjacent[edgeCursor++];
                EdgeEvaluations++;
                if (closed.Contains(edge.To) || edge.Gate.Evaluate(read) != Truth.True) continue;
                var candidate = distance[expanding] + edge.Meters;
                if (!double.IsFinite(candidate)) throw new InvalidDataException("Route distance exceeds numeric range.");
                if (distance.TryGetValue(edge.To, out var old) && old <= candidate) continue;
                distance[edge.To] = candidate; previous[edge.To] = expanding;
                frontier.Enqueue(edge.To, candidate);
            }
        }
    }
}
