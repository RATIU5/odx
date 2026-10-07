package app

import "core:time"

Duration :: distinct i64

Nanosecond :: Duration(1)

MICROSECOND :: Duration(1000)

Second :: time.Duration(1e9)

MINUTE :: time.Duration(60e9)

WIDTH :: int(4)

Size :: size_of(int)

ALIGN :: align_of(int)
