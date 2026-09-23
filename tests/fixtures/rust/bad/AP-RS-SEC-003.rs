use serde::Deserialize;

// ruleid: slopguard.rs.serde-missing-deny-unknown
#[derive(Deserialize)]
pub struct Config {
    pub timeout_secs: u64,
    pub max_connections: usize,
}
