using DuelView.RogueTopology;

static RoomTemplate T(string id, int weight, params (string Port, string Connector)[] ports) =>
    new(id, weight, ports.ToDictionary(p => p.Port, p => p.Connector));
static void Check(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
static TopologyLayout Solve(TopologyProblem problem, ulong seed = 0) =>
    TopologySolver.Solve(problem, seed) ?? throw new InvalidOperationException("Expected a valid layout.");

// The final edge forces the middle room, which must requeue the first edge.
var chain = new TopologyProblem("A", "C", [
    new("A", [T("wrong", 100, ("east", "blue")), T("right", 1, ("east", "red")),
        T("boundary-leak", 100, ("east", "red"), ("north", "red"))]),
    new("B", [T("red", 1, ("west", "red"), ("east", "red")),
        T("blue", 1, ("west", "blue"), ("east", "blue"))]),
    new("C", [T("end", 1, ("west", "red"))])],
    [new("A", "east", "B", "west"), new("B", "east", "C", "west")]);
var path = Solve(chain);
Check(path.StartRoomId == "A" && path.GoalRoomId == "C" && path.RoomIds.SequenceEqual(new[] { "A", "B", "C" }), "Room lookup contract.");
Check(path.GetTemplateId("A") == "right" && path.GetTemplateId("B") == "red", "Propagation or boundary filtering failed.");
Check(path.GetExits("A").SequenceEqual(new[] { new RoomExit("east", "B", "west", "red") }) &&
    path.GetExits("B").Contains(new("west", "A", "east", "red")), "Open exits must be reciprocal.");

// Arc consistency alone accepts this odd cycle; every complete branch must fail.
RoomTemplate[] flip = [T("zero", 1, ("in", "0"), ("out", "1")), T("one", 1, ("in", "1"), ("out", "0"))];
var odd = new TopologyProblem("A", "C", [new("A", flip), new("B", flip), new("C", flip)],
    [new("A", "out", "B", "in"), new("B", "out", "C", "in"), new("C", "out", "A", "in")]);
Check(TopologySolver.Solve(odd, 0) is null, "Impossible cyclic constraints must return null.");
Check(TopologySolver.Solve(chain with { Rooms = [new("A", []), chain.Rooms[1], chain.Rooms[2]] }, 0) is null,
    "Empty domains must return null.");

// Seed zero draws the heavily weighted closed branch first; backtrack to the open one.
var gate = new TopologyProblem("A", "B", [
    new("A", [T("closed", int.MaxValue), T("open", 1, ("out", "door"))]),
    new("B", [T("closed", 1), T("open", 1, ("in", "door"))])],
    [new("A", "out", "B", "in", Required: false)]);
Check(Solve(gate).GetTemplateId("A") == "open", "Optional gate must open to reach the goal.");
Check(TopologySolver.Solve(gate with { Rooms = [new("A", [T("closed", 1)]), new("B", [T("closed", 1)])] }, 0) is null,
    "Compatible walls do not form a path.");
var closed = Solve(gate with { GoalRoomId = "A" });
Check(closed.GetExits("A").Count == 0 && closed.GetExits("B").Count == 0, "Closed optional links must not appear in exits.");
Check(TopologySolver.Solve(gate with { Links = [new("A", "out", "B", "in")],
    Rooms = [new("A", [T("closed", 1)]), new("B", [T("closed", 1)])] }, 0) is null,
    "A required link must reject walls.");

// Start/goal connectivity alone permits an isolated room; the new opt-in rejects it.
var isolated = gate with { Rooms = [.. gate.Rooms, new("C", [T("isolated", 1)])] };
Check(TopologySolver.Solve(isolated, 0) is not null &&
    TopologySolver.Solve(isolated with { RequireAllRoomsReachable = true }, 0) is null,
    "All-room connectivity must reject an isolated room.");
Check(TopologySolver.Solve(gate with { MinimumStartExits = 2 }, 0) is null,
    "The minimum start degree must reject a one-exit map.");

var weighted = new TopologyProblem("solo", "solo", [new("solo", [T("light", 1), T("heavy", 9)])], []);
int heavy = 0;
for (ulong seed = 0; seed < 1024; ++seed)
{
    var selected = Solve(weighted, seed).GetTemplateId("solo");
    if (selected == "heavy") ++heavy;
    Check(selected == Solve(weighted, seed).GetTemplateId("solo"), $"Seed {seed} changed on replay.");
}
Check(heavy is > 870 and < 970, $"Expected roughly 90% heavy picks, got {heavy}/1024.");
var reordered = gate with {
    Rooms = gate.Rooms.Reverse().Select(r => r with { Candidates = r.Candidates.Reverse().ToArray() }).ToArray(),
    Links = [new("B", "in", "A", "out", Required: false)], GoalRoomId = "A"
};
for (ulong seed = 0; seed < 32; ++seed)
{
    var original = Solve(gate with { GoalRoomId = "A" }, seed);
    var replay = Solve(reordered, seed);
    Check(original.RoomIds.SequenceEqual(replay.RoomIds) && original.RoomIds.All(id =>
        original.GetTemplateId(id) == replay.GetTemplateId(id) && original.GetExits(id).SequenceEqual(replay.GetExits(id))),
        $"Input ordering changed seed {seed}.");
}
// Fixed seed vector for the public weighted choice, alongside the distribution check.
Check(Solve(weighted, 0).GetTemplateId("solo") == "heavy" && Solve(weighted, 17).GetTemplateId("solo") == "light",
    "Fixed seed vector changed.");
Console.WriteLine($"Topology tests passed; heavy weight: {heavy}/1024.");
