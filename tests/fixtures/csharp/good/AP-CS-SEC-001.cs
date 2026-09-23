using System.Data.SqlClient;

// ok: slopguard.cs.sql-string-interpolation
public class UserRepo
{
    public void FindUser(string userId, SqlConnection conn)
    {
        var cmd = new SqlCommand("SELECT * FROM users WHERE id = @id", conn);
        cmd.Parameters.AddWithValue("@id", userId);
        cmd.ExecuteReader();
    }
}
