using System.Data.SqlClient;

// ruleid: slopguard.cs.sql-string-interpolation
public class UserRepo
{
    public void FindUser(string userId, SqlConnection conn)
    {
        var cmd = new SqlCommand($"SELECT * FROM users WHERE id = {userId}", conn);
        cmd.ExecuteReader();
    }
}
