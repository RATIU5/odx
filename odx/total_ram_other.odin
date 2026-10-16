#+build !darwin
package odx

import si "core:sys/info"

// In bytes.
@(require_results)
total_ram :: proc() -> (total: i64, ok: bool) {
	total, _, _, _, ok = si.ram_stats()
	return
}
