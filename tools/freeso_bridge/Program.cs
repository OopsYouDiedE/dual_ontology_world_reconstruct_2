using System;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;

namespace DuelView.FreeSOBridge
{
    internal static class Program
    {
        private static int Main(string[] args)
        {
            if (args.Length != 3)
            {
                Console.Error.WriteLine("Usage: FreeSOSnapshot.exe <client-directory> <trusted-input.fsov> <output.json>");
                return 2;
            }
            try
            {
                var root = Path.GetFullPath(args[0]);
                AppDomain.CurrentDomain.AssemblyResolve += (sender, request) => {
                    var file = new AssemblyName(request.Name).Name + ".dll";
                    foreach (var directory in new[] { root, Path.Combine(root, "Monogame", "WindowsGL") })
                    {
                        var candidate = Path.Combine(directory, file);
                        if (File.Exists(candidate)) return Assembly.LoadFrom(candidate);
                    }
                    return null;
                };
                Run(args[1], args[2]);
                return 0;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine(error);
                return 1;
            }
        }

        // Install dependency resolution before the JIT sees the upstream types.
        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void Run(string input, string output)
        {
            SnapshotBridge.ExportFile(input, output);
        }
    }
}
