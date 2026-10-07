package app

import "core:fmt"
import "core:sync/chan"

LIMIT :: 5

My_Int :: int

println :: fmt.println

UPDATES :: chan.Chan(int)

SIZE :: size_of(int)

OTHER_LIMIT :: LIMIT

PAREN_LIMIT :: (LIMIT)

typed_limit: int : LIMIT
