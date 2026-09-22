package platform

// This example's edge policy permits core:os imports and package state.

import "core:fmt"
import "core:os"

import "../core"

world: core.World

main :: proc() {
	world = {hp = core.MAX_HP}
	world = core.step(world, {damage = len(os.args)})
	fmt.println(world)
}
