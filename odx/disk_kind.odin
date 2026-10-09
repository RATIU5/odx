package odx

import "core:sys/posix"

Disk_Kind :: enum u8 {
	// Nothing odx can reach: no entry, a link that doesn't resolve, or a directory on the way that
	// can't be searched. Opening the path fails for the same reason.
	Missing,
	File,
	Dir,
	// A FIFO, a socket or a device. Opening a FIFO waits for a writer, and reading a device may
	// never end, so odx opens none.
	Special,
}

// What `path` names once every link is followed. It reads the kind with `stat`, which opens
// nothing, where `os.stat`, `os.is_file` and `os.is_directory` open the path first. Every path that
// the repo or `odx.json` chooses goes through here before odx opens it.
disk_kind :: proc(path: string) -> Disk_Kind {
	buffer: [posix.PATH_MAX]u8
	if len(path) >= len(buffer) {
		return .Missing
	}
	copy(buffer[:], path)
	info: posix.stat_t
	switch {
	case posix.stat(cstring(raw_data(buffer[:])), &info) != .OK:
		return .Missing
	case posix.S_ISREG(info.st_mode):
		return .File
	case posix.S_ISDIR(info.st_mode):
		return .Dir
	}
	return .Special
}
