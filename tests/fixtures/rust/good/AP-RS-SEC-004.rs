fn compute_offset(base: u32, delta: u32) -> Option<u32> {
    // ok: slopguard.rs.integer-arithmetic-overflow
    base.checked_add(delta)
}
