use serde::Deserialize;

// ok: slopguard.rs.serde-missing-deny-unknown
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub timeout_secs: u64,
    pub max_connections: usize,
}
