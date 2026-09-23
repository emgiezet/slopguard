// ok: slopguard.rs.unsafe-block
unsafe fn write_value(ptr: *mut u32, val: u32) {
    // SAFETY: caller guarantees ptr is non-null, properly aligned,
    // and valid for writes for the lifetime of this call.
    unsafe {
        *ptr = val;
    }
}
