package app

import gzip "core:compress/gzip"
import fmt "core:fmt"

import lib "../lib"

show :: proc() {
	fmt.println(lib.LIMIT, gzip.GZIP_MAX_PAYLOAD_SIZE)
}
