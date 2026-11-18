namespace DuelView.RogueTopology;

public sealed record RoomTemplate(string Id, int Weight, IReadOnlyDictionary<string, string> Ports);
public sealed record RoomSlot(string Id, IReadOnlyList<RoomTemplate> Candidates);
public sealed record RoomLink(string RoomA, string PortA, string RoomB, string PortB, bool Required = true);
public sealed record TopologyProblem(string StartRoomId, string GoalRoomId,
    IReadOnlyList<RoomSlot> Rooms, IReadOnlyList<RoomLink> Links)
{
    public bool RequireAllRoomsReachable { get; init; }
    public int MinimumStartExits { get; init; }
}
public sealed record RoomExit(string Port, string DestinationRoomId, string DestinationPort, string Connector);

public sealed class TopologyLayout
{
    private readonly Dictionary<string, string> _templates;
    private readonly Dictionary<string, IReadOnlyList<RoomExit>> _exits;
    public string StartRoomId { get; }
    public string GoalRoomId { get; }
    public IReadOnlyList<string> RoomIds { get; }
    public string GetTemplateId(string roomId) => _templates[roomId];
    public IReadOnlyList<RoomExit> GetExits(string roomId) => _exits[roomId];

    internal TopologyLayout(string start, string goal, string[] ids, RoomTemplate[] rooms,
        IEnumerable<(int A, int B, string PortA, string PortB)> links)
    {
        StartRoomId = start;
        GoalRoomId = goal;
        RoomIds = Array.AsReadOnly(ids);
        _templates = ids.Select((id, i) => (id, rooms[i].Id))
            .ToDictionary(x => x.id, x => x.Id, StringComparer.Ordinal);
        var exits = ids.Select(_ => new List<RoomExit>()).ToArray();
        foreach (var (a, b, portA, portB) in links)
        {
            if (!rooms[a].Ports.TryGetValue(portA, out var connector)) continue;
            exits[a].Add(new(portA, ids[b], portB, connector));
            exits[b].Add(new(portB, ids[a], portA, connector));
        }
        _exits = ids.Select((id, i) => (id, exits[i]))
            .ToDictionary(x => x.id, x => (IReadOnlyList<RoomExit>)Array.AsReadOnly(
                x.Item2.OrderBy(exit => exit.Port, StringComparer.Ordinal).ToArray()), StringComparer.Ordinal);
    }
}

public static class TopologySolver
{
    /// <summary>Returns a layout with a start-to-goal path, or null if no such assignment exists.</summary>
    public static TopologyLayout? Solve(TopologyProblem problem, ulong seed) => new Search(problem, seed).Solve();

    private sealed record Edge(int A, int B, string PortA, string PortB, bool Required)
    {
        public bool Supports(RoomTemplate a, RoomTemplate b)
        {
            string? left = a.Ports.GetValueOrDefault(PortA);
            string? right = b.Ports.GetValueOrDefault(PortB);
            return left == right && (left is not null || !Required);
        }
    }

    private sealed class Search
    {
        private readonly string[] _ids;
        private readonly int _start, _goal, _minimumStartExits;
        private readonly bool _requireAllRoomsReachable;
        private readonly List<RoomTemplate>[] _initial;
        private readonly Edge[] _edges;
        private readonly List<int>[] _incident;
        private ulong _state;

        public Search(TopologyProblem problem, ulong seed)
        {
            ArgumentNullException.ThrowIfNull(problem);
            _state = seed;
            Require(problem.MinimumStartExits >= 0, "Minimum start exits cannot be negative.");
            _minimumStartExits = problem.MinimumStartExits;
            _requireAllRoomsReachable = problem.RequireAllRoomsReachable;
            var rooms = problem.Rooms.OrderBy(r => r.Id, StringComparer.Ordinal).ToArray();
            _ids = rooms.Select(r => r.Id).ToArray();
            var indices = new Dictionary<string, int>(StringComparer.Ordinal);
            for (int i = 0; i < _ids.Length; ++i)
                Require(Valid(_ids[i]) && indices.TryAdd(_ids[i], i), "Room IDs must be nonempty and unique.");
            _start = Index(problem.StartRoomId);
            _goal = Index(problem.GoalRoomId);
            var ports = rooms.Select(_ => new HashSet<string>(StringComparer.Ordinal)).ToArray();
            _edges = problem.Links.Select(link =>
            {
                int a = Index(link.RoomA), b = Index(link.RoomB);
                Require(a != b, "Links must connect different rooms.");
                Require(Valid(link.PortA) && Valid(link.PortB) && ports[a].Add(link.PortA) && ports[b].Add(link.PortB),
                    "Each room port must be nonempty and linked at most once.");
                return a < b ? new Edge(a, b, link.PortA, link.PortB, link.Required)
                    : new Edge(b, a, link.PortB, link.PortA, link.Required);
            }).OrderBy(e => e.A).ThenBy(e => e.PortA, StringComparer.Ordinal).ToArray();
            _incident = rooms.Select(_ => new List<int>()).ToArray();
            for (int i = 0; i < _edges.Length; ++i)
            {
                _incident[_edges[i].A].Add(i);
                _incident[_edges[i].B].Add(i);
            }
            _initial = rooms.Select((room, i) =>
            {
                var seen = new HashSet<string>(StringComparer.Ordinal);
                var candidates = new List<RoomTemplate>();
                foreach (var candidate in room.Candidates.OrderBy(c => c.Id, StringComparer.Ordinal))
                {
                    Require(Valid(candidate.Id) && seen.Add(candidate.Id) && candidate.Weight > 0,
                        "Within a room, template IDs must be nonempty and unique, and weights positive.");
                    Require(candidate.Ports.All(p => Valid(p.Key) && Valid(p.Value)),
                        "Port names and connector labels must be nonempty.");
                    // An unlinked face is a boundary wall. Snapshot with ordinal port matching.
                    if (candidate.Ports.Keys.All(ports[i].Contains))
                        candidates.Add(candidate with { Ports = new Dictionary<string, string>(candidate.Ports, StringComparer.Ordinal) });
                }
                return candidates;
            }).ToArray();

            int Index(string id) => Valid(id) && indices.TryGetValue(id, out int i)
                ? i : throw new ArgumentException($"Unknown room ID: '{id}'.", nameof(problem));
        }

        private static bool Valid(string value) => !string.IsNullOrWhiteSpace(value);
        private static void Require(bool condition, string message)
        {
            if (!condition) throw new ArgumentException(message, "problem");
        }

        public TopologyLayout? Solve()
        {
            var pending = new Stack<IEnumerator<List<RoomTemplate>[]>>();
            var state = _initial;
            try
            {
                while (true)
                {
                    if (Propagate(state) && CanMeetConnectivity(state))
                    {
                        int room = -1;
                        for (int i = 0; i < state.Length; ++i)
                            if (state[i].Count > 1 && (room < 0 || state[i].Count < state[room].Count)) room = i;
                        if (room < 0)
                            return new(_ids[_start], _ids[_goal], _ids, state.Select(d => d[0]).ToArray(),
                                _edges.Select(e => (e.A, e.B, e.PortA, e.PortB)));
                        pending.Push(Branches(state, room).GetEnumerator());
                    }
                    while (pending.Count > 0 && !pending.Peek().MoveNext()) pending.Pop().Dispose();
                    if (pending.Count == 0) return null;
                    state = pending.Peek().Current;
                }
            }
            finally
            {
                while (pending.TryPop(out var branch)) branch.Dispose();
            }
        }

        private bool Propagate(List<RoomTemplate>[] domains)
        {
            if (domains.Any(d => d.Count == 0)) return false;
            var queue = new Queue<int>(Enumerable.Range(0, _edges.Length));
            var queued = Enumerable.Repeat(true, _edges.Length).ToArray();
            while (queue.TryDequeue(out int i))
            {
                queued[i] = false;
                var e = _edges[i];
                int removedA = domains[e.A].RemoveAll(a => !domains[e.B].Any(b => e.Supports(a, b)));
                int removedB = domains[e.B].RemoveAll(b => !domains[e.A].Any(a => e.Supports(a, b)));
                if (domains[e.A].Count == 0 || domains[e.B].Count == 0) return false;
                if (removedA > 0) EnqueueNeighbors(e.A);
                if (removedB > 0) EnqueueNeighbors(e.B);

                void EnqueueNeighbors(int room)
                {
                    foreach (int j in _incident[room])
                        if (!queued[j] && j != i) { queued[j] = true; queue.Enqueue(j); }
                }
            }
            return true;
        }

        private bool CanMeetConnectivity(List<RoomTemplate>[] domains)
        {
            // Possible edges bound reachability while domains are unresolved. At a leaf
            // every domain is a singleton, so these are exactly the actual open edges.
            var open = _edges.Select(edge => domains[edge.A].Any(a => a.Ports.ContainsKey(edge.PortA) &&
                domains[edge.B].Any(b => edge.Supports(a, b)))).ToArray();
            if (_incident[_start].Count(i => open[i]) < _minimumStartExits) return false;
            var seen = new bool[_ids.Length];
            var queue = new Queue<int>();
            seen[_start] = true;
            queue.Enqueue(_start);
            int reached = 1;
            while (queue.TryDequeue(out int room))
            {
                if (!_requireAllRoomsReachable && room == _goal) return true;
                foreach (int edgeIndex in _incident[room])
                {
                    if (!open[edgeIndex]) continue;
                    var edge = _edges[edgeIndex];
                    int other = edge.A == room ? edge.B : edge.A;
                    if (seen[other]) continue;
                    seen[other] = true;
                    ++reached;
                    queue.Enqueue(other);
                }
            }
            return _requireAllRoomsReachable && reached == _ids.Length;
        }

        private IEnumerable<List<RoomTemplate>[]> Branches(List<RoomTemplate>[] domains, int room)
        {
            var remaining = new List<RoomTemplate>(domains[room]);
            ulong total = (ulong)remaining.Sum(c => (long)c.Weight);
            while (remaining.Count > 0)
            {
                ulong draw = NextBelow(total);
                int i = 0;
                while (draw >= (ulong)remaining[i].Weight) draw -= (ulong)remaining[i++].Weight;
                var selected = remaining[i];
                total -= (ulong)selected.Weight;
                remaining.RemoveAt(i);
                var branch = domains.Select(d => new List<RoomTemplate>(d)).ToArray();
                branch[room] = [selected];
                yield return branch;
            }
        }

        private ulong NextBelow(ulong bound)
        {
            // SplitMix64 plus rejection sampling, independent of framework RNG and modulo bias.
            unchecked
            {
                ulong threshold = (0UL - bound) % bound;
                while (true)
                {
                    ulong z = (_state += 0x9E3779B97F4A7C15UL);
                    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
                    z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
                    z ^= z >> 31;
                    if (z >= threshold) return z % bound;
                }
            }
        }
    }
}
