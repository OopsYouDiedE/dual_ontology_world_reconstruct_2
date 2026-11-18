# Rogue room topology

Standalone .NET 8 library in `DuelView.RogueTopology`. The caller supplies a graph
of potential adjacencies, with candidate templates for each room slot. Each
candidate maps its open ports to connector labels; omitted ports are walls.
A required link matches two open ports with the same label. An optional link
also allows two walls. Open ports facing an unlinked boundary eliminate that
candidate. IDs and labels use ordinal, case-sensitive matching.

`TopologySolver.Solve(TopologyProblem problem, ulong seed)` returns a read-only
`TopologyLayout` or `null` for a well-formed but unsatisfiable problem. It
validates room/link IDs and template weights before searching. A layout always
has an open path from `StartRoomId` to `GoalRoomId`; other slots may be isolated by default. Set `RequireAllRoomsReachable` to
require every slot to be connected, and `MinimumStartExits` to require a minimum
number of open links at the starting room. These constraints prune impossible
branches and are checked on the completed layout.

- `RoomIds` lists all room IDs in ordinal order.
- `GetTemplateId(string roomId)` returns the selected template ID.
- `GetExits(string roomId)` lists the room's open, bidirectional topology exits
  in ordinal port order. Gameplay locks or transient state can filter this list
  at the caller. Both lookups throw `KeyNotFoundException` for an unknown room.
- Each `RoomExit` exposes `Port`, `DestinationRoomId`, `DestinationPort`, and
  `Connector`.

The solver propagates adjacency constraints to a fixed point, checks possible
start-to-goal reachability, and collapses the smallest remaining non-singleton
domain. Ties use room ID order. Candidates are drawn by positive integer weight,
without replacement when backtracking. The fixed SplitMix64 algorithm and
canonical input ordering give repeatable choices for the same seed and inputs.
Weights govern individual draws; backtracking conditions the returned layout on
validity. Worst-case search is exponential.

Run the dependency-free unit tests from the repository root:

```powershell
dotnet run --project core/rogue_topology/tests/DuelView.RogueTopology.Tests.csproj
```
