fn parse_number(s: &str) -> i32 {
    // ruleid: slopguard.rs.unwrap-in-library
    s.parse::<i32>().unwrap()
}

fn get_first(v: &[i32]) -> i32 {
    // ruleid: slopguard.rs.unwrap-in-library
    v.first().copied().expect("slice must not be empty")
}
