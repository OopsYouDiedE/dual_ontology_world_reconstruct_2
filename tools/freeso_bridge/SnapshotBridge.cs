using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using FSO.LotView.Model;
using FSO.SimAntics;
using FSO.SimAntics.Marshals;
using FSO.SimAntics.Engine;
using FSO.SimAntics.Model.TSOPlatform;

namespace DuelView.FreeSOBridge
{
    public static class SnapshotBridge
    {
        private static readonly int ProcessId = GetProcessId();
        private static int GetProcessId()
        {
            using (var process = System.Diagnostics.Process.GetCurrentProcess()) return process.Id;
        }

        // Only use on the owning VM thread, at a stable tick boundary.
        public static void ExportLive(VM vm, string output, IDictionary<short, ushort> observedFreewill = null)
        {
            if (vm == null) throw new ArgumentNullException("vm");
            Export(vm.Save(false), output, "live-vm", null, observedFreewill);
        }

        // For trusted local FreeSO saves only. Upstream Deserialize allocates from file counts.
        public static VMMarshal ReadNative(BinaryReader reader)
        {
            var start = reader.BaseStream.Position;
            if (Encoding.ASCII.GetString(reader.ReadBytes(4)) != "FSOv")
                throw new InvalidDataException("Expected a native FSOv VM snapshot (.fsov), not a blueprint or character export.");
            var version = reader.ReadInt32();
            if (version < 1 || version > VMMarshal.LATEST_VERSION)
                throw new InvalidDataException("Unsupported native snapshot version: " + version);
            reader.BaseStream.Position = start;
            var state = new VMMarshal();
            state.Deserialize(reader);
            return state;
        }

        public static void ExportFile(string input, string output)
        {
            if (String.Equals(Path.GetFullPath(input), Path.GetFullPath(output), StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("Source snapshot and JSON output must be different files.");
            using (var file = File.OpenRead(input))
            using (var reader = new BinaryReader(file))
            using (var sha = SHA256.Create())
            {
                var digest = BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "").ToLowerInvariant();
                file.Position = 0;
                Export(ReadNative(reader), output, "fsov", digest);
            }
        }

        private static string Membership(VMTSOLotState lot, uint id)
        {
            if (lot == null || lot.CommunityLot || id == 0) return "unknown";
            if (lot.OwnerID == id) return "owner";
            if (lot.BuildRoommates != null && lot.BuildRoommates.Contains(id)) return "build_roommate";
            if (lot.Roommates != null && lot.Roommates.Contains(id)) return "roommate";
            return "not_listed";
        }

        private static object Activity(VMMarshal state, int index, short avatarId, IDictionary<short, ushort> observedFreewill)
        {
            if (state.Version <= 4 || state.Threads == null || state.Threads.Length != state.Entities.Length)
                return new { status = "unavailable" };
            var thread = state.Threads[index];
            if (thread == null || thread.Queue == null || thread.ActiveQueueBlock < -1 || thread.ActiveQueueBlock >= thread.Queue.Length)
                return new { status = "unavailable" };
            var frame = thread.Stack != null && thread.Stack.Length > 0 ? thread.Stack[thread.Stack.Length - 1] : null;
            var stack = frame == null ? null : new {
                routine_id = frame.RoutineID, instruction_pointer = frame.InstructionPointer,
                callee_object_id = frame.Callee, stack_object_id = frame.StackObject, action_tree = frame.ActionTree
            };
            if (thread.ActiveQueueBlock == -1)
                return new { status = "no_active_action", queued_count = thread.Queue.Length, stack };
            var action = thread.Queue[thread.ActiveQueueBlock];
            if (action == null) return new { status = "unavailable" };
            ushort observedUid;
            string evidence = observedFreewill != null && observedFreewill.TryGetValue(avatarId, out observedUid) && observedUid == action.UID
                ? "vm_find_best_action" : null;
            return new {
                status = "active", queued_count = thread.Queue.Length, stack,
                action = new {
                    uid = action.UID, name = action.Name, routine_id = action.RoutineID,
                    interaction_number = action.InteractionNumber, callee_object_id = action.Callee,
                    stack_object_id = action.StackObject, priority = action.Priority, queue_mode = action.Mode.ToString(),
                    autonomous_priority = action.Priority == (short)VMQueuePriority.Autonomous,
                    freewill_evidence = evidence
                }
            };
        }

        private static void Export(VMMarshal state, string output, string kind, string digest, IDictionary<short, ushort> observedFreewill = null)
        {
            var architecture = state.Context.Architecture;
            var clock = state.Context.Clock;
            var size = checked(architecture.Width * architecture.Height);
            var walls = new List<object>();
            var floors = new List<object>();
            for (int floor = 0; floor < architecture.Stories; floor++)
            {
                for (int i = 0; i < size; i++)
                {
                    var wall = architecture.Walls[floor][i];
                    var pattern = architecture.Floors[floor][i].Pattern;
                    if ((int)wall.Segments != 0)
                        walls.Add(new {
                            x = i % architecture.Width, y = i / architecture.Width, level = floor + 1,
                            mask = (int)wall.Segments, segments = wall.Segments.ToString(),
                            patterns = new[] { wall.TopLeftPattern, wall.TopRightPattern, wall.BottomLeftPattern, wall.BottomRightPattern },
                            styles = new[] { wall.TopLeftStyle, wall.TopRightStyle }
                        });
                    if (pattern != 0)
                        floors.Add(new { x = i % architecture.Width, y = i / architecture.Width, level = floor + 1, pattern });
                }
            }
            var avatars = new List<object>();
            var tsoLot = state.PlatformState as VMTSOLotState;
            for (int i = 0; i < state.Entities.Length; i++)
            {
                // VM.Save populates Entities and Threads in the same order.
                var avatar = state.Entities[i] as VMAvatarMarshal;
                if (avatar == null) continue;
                var pos = avatar.Position;
                avatars.Add(new {
                    object_id = avatar.ObjectID, persist_id = avatar.PersistID, guid = avatar.GUID,
                    x16 = pos.x, y16 = pos.y, level = pos.Level,
                    placed = pos != LotTilePos.OUT_OF_WORLD && pos.Level >= 1 && pos.Level <= architecture.Stories
                        && pos.TileX >= 0 && pos.TileX < architecture.Width && pos.TileY >= 0 && pos.TileY < architecture.Height,
                    heading_radians = avatar.RadianDirection,
                    lot_membership = Membership(tsoLot, avatar.PersistID),
                    activity = Activity(state, i, avatar.ObjectID, observedFreewill)
                });
            }
            var document = new {
                schema = "freeso.lot-snapshot.v1",
                source = new { kind, format_version = state.Version, sha256 = digest, ts1 = state.TS1,
                    room_id = kind == "live-vm" ? Path.GetFileNameWithoutExtension(output) : null,
                    pid = kind == "live-vm" ? (int?)ProcessId : null },
                tick = clock.Ticks,
                lot = new { width = architecture.Width, height = architecture.Height, stories = architecture.Stories, walls, floors },
                avatars
            };
            var json = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue }.Serialize(document);
            output = Path.GetFullPath(output);
            var partial = output + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(partial, json, new UTF8Encoding(false));
                if (File.Exists(output)) File.Replace(partial, output, null);
                else File.Move(partial, output);
            }
            finally { if (File.Exists(partial)) File.Delete(partial); }
        }
    }
}
