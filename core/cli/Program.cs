using System.Text;
Console.InputEncoding = new UTF8Encoding(false);
Console.OutputEncoding = new UTF8Encoding(false);
if(args.FirstOrDefault()=="--render-cli-log") { ReadableEventLog.Render(args); return; }
if(args.FirstOrDefault()=="--story-authoring-view") { Environment.ExitCode=ScenarioAuthoring.Run(args); return; }
if(args.FirstOrDefault()=="--export-spatial-data") { Environment.ExitCode=SpatialPublication.Run(args); return; }
if(args.FirstOrDefault()=="--fit-seating") { Environment.ExitCode=SeatingFit.Run(args); return; }
if(args.FirstOrDefault()=="--verify-character-actions") { Environment.ExitCode=NativeCli.ValidateContent(); return; }
NativeCli.Run();
