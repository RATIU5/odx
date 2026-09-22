#+vet explicit-allocators
package domain

Domain_Failure :: enum { None, Invalid }
Storage_Failure :: enum { None, Unavailable }
State :: struct { count: int }

@(require_results)
advance :: proc(state: ^State) -> Domain_Failure {
	state.count += 1
	return .None
}

@(require_results)
store :: proc() -> Storage_Failure {
	return .None
}
