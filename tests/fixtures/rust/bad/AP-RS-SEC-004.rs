fn compute_offset(base: u32, delta: u32) -> u32 {
    // ruleid: slopguard.rs.integer-arithmetic-overflow
    base + delta  // panics in debug, wraps silently in release
}
