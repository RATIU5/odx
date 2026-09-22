package app

import "../adapters"
import "../domain"

state: domain.State

main :: proc() {
	_ = adapters.process_id()
	_ = domain.advance(&state)
}
