package platform

// An edge package: the only place that may import core:os and hold process state.

import "core:fmt"
import "core:os"

import "../core"

world: core.World

main :: proc() {
	world = {hp = core.MAX_HP}
	world = core.step(world, {damage = len(os.args)})
	fmt.println(world)
}
