use std::num::ParseIntError;

// ok: slopguard.rs.unwrap-in-library
fn parse_number(s: &str) -> Result<i32, ParseIntError> {
    s.parse::<i32>()
}

fn get_first(v: &[i32]) -> Option<i32> {
    v.first().copied()
}
