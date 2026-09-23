using System.Diagnostics;

// ok: slopguard.cs.process-start-user-input
public class Runner
{
    private static readonly HashSet<string> Allowed = new() { "report", "export" };

    public void Execute(string command)
    {
        if (!Allowed.Contains(command)) throw new ArgumentException("Unknown command");
        var psi = new ProcessStartInfo
        {
            FileName = "myapp",
            Arguments = command,
            UseShellExecute = false
        };
        Process.Start(psi);
    }
}
