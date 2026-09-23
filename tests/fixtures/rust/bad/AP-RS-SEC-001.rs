// ruleid: slopguard.rs.unsafe-block
unsafe fn write_value(ptr: *mut u32, val: u32) {
    // No SAFETY: comment explaining invariants
    unsafe {
        *ptr = val;
    }
}
