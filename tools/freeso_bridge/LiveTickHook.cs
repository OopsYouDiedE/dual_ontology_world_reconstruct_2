using System;
using System.Diagnostics;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using FSO.SimAntics;

namespace DuelView.FreeSOBridge
{
    // Injected only into the sandbox screen, whose update runs on the VM owner thread.
    internal static class LiveTickHook
    {
        private static readonly string Output = ReadOutput();
        private static readonly Stopwatch Monotonic = Stopwatch.StartNew();
        private static WeakReference BoundVm;
        private static FileStream OutputLease;
        private static bool Stopped;
        private static long NextAttempt;
        private static long LastTick = -1;

        internal static long? BeforeUpdate(VM vm)
        {
            if (Output == null || Stopped || vm == null) return null;
            if (BoundVm != null && !Object.ReferenceEquals(BoundVm.Target, vm))
            {
                Stopped = true;
                Log("The sandbox opened another VM. Restart the client from Godot to bind a different lot.");
                return null;
            }
            if (Monotonic.ElapsedMilliseconds < NextAttempt) return null;
            return vm.Context != null && vm.Context.Clock != null ? (long?)vm.Context.Clock.Ticks : null;
        }

        internal static void AfterUpdate(VM vm, long? before)
        {
            if (!before.HasValue || !vm.Ready || vm.Context == null || vm.Context.Architecture == null || vm.Context.Clock == null)
                return;
            var tick = vm.Context.Clock.Ticks;
            if (tick <= before.Value || tick <= LastTick) return;
            NextAttempt = Monotonic.ElapsedMilliseconds + 1000;
            if (BoundVm == null) BoundVm = new WeakReference(vm);
            try
            {
                if (OutputLease == null)
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(Output));
                    // Held until process exit. Leave the file in place so the lock identity is stable.
                    OutputLease = new FileStream(Output + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
                }
                SnapshotBridge.ExportLive(vm, Output, ObservedFreewill(vm));
                if (LastTick < 0) Log("First native sandbox snapshot: tick " + tick + " -> " + Output);
                LastTick = tick;
                NextAttempt = Monotonic.ElapsedMilliseconds + 1000;
            }
            catch (Exception error)
            {
                Log("Snapshot for tick " + tick + " failed: " + error.Message);
                NextAttempt = Monotonic.ElapsedMilliseconds + 5000;
            }
        }

        private static IDictionary<short, ushort> ObservedFreewill(VM vm)
        {
            var observed = new Dictionary<short, ushort>();
            foreach (var entity in vm.Entities)
            {
                if (!(entity is VMAvatar) || entity.Thread == null) continue;
                var thread = entity.Thread;
                var index = thread.ActiveQueueBlock;
                if (index < 0 || index >= thread.Queue.Count) continue;
                var action = thread.Queue[index];
                if (action != null && action.DuelViewSelectedByFindBestAction)
                    observed[entity.ObjectID] = action.UID;
            }
            return observed;
        }

        private static string ReadOutput()
        {
            var value = Environment.GetEnvironmentVariable("FREESO_VM_SNAPSHOT_PATH");
            if (String.IsNullOrWhiteSpace(value)) return null;
            try
            {
                if (!Path.IsPathRooted(value) || Path.GetPathRoot(value).Length < 3
                    || !Regex.IsMatch(Path.GetFileName(value), @"\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\.json\z", RegexOptions.CultureInvariant))
                    throw new ArgumentException("Expected an absolute normalized path ending in <room-id>.json.");
                return Path.GetFullPath(value);
            }
            catch (Exception error)
            {
                Log("FREESO_VM_SNAPSHOT_PATH disabled: " + error.Message);
                return null;
            }
        }

        private static void Log(string message)
        {
            Console.Error.WriteLine("[DuelView FreeSO bridge] " + message);
        }
    }
}
