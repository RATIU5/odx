package app

State :: struct {
	count: int,
}

STATE := State{}

state := State{}

origin := State {
	count = 1,
}

bump :: proc() {
	STATE.count += 1
	state.count += 1
}
