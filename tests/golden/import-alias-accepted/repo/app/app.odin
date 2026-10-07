package app

import compress_gzip "core:compress/gzip"
import "core:fmt"
import str "core:strings"

import util "../lib"

show :: proc() {
	fmt.println(util.LIMIT, compress_gzip.GZIP_MAX_PAYLOAD_SIZE, str.to_upper("a"))
}
