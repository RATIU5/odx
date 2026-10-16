package odx

import "core:sys/unix"

// In bytes. dev-2026-10 dies on any program that calls `core:sys/info.ram_stats` for macOS, so the
// number comes from sysctl here.
@(require_results)
total_ram :: proc() -> (total: i64, ok: bool) {
	bytes: u64
	ok = unix.sysctlbyname("hw.memsize", &bytes)
	return i64(bytes), ok
}
