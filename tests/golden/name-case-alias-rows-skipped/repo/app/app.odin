package app

import "core:fmt"
import "core:sync/chan"

LIMIT :: 5

my_int :: int

Println :: fmt.println

UPDATES :: chan.Chan(int)

Size :: size_of(int)

other_limit :: LIMIT

Paren_limit :: (LIMIT)

typed_limit: int : LIMIT
