package adapters

import "core:os"

request_count: int

process_id :: proc() -> int {
	request_count += 1
	return int(os.get_pid())
}
