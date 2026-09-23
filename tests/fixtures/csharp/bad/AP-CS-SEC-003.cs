using System.Diagnostics;

// ruleid: slopguard.cs.process-start-user-input
public class Runner
{
    public void Execute(string userCommand)
    {
        Process.Start(new ProcessStartInfo($"cmd /c {userCommand}"));
    }
}
