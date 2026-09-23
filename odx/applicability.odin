package odx

import "core:fmt"
import "core:slice"
import "core:strings"

check_applies :: proc(cfg: ^Config, spec: Check_Spec, role: string) -> bool {
	if !role_applies(spec, role) {return false}
	#partial switch spec.kind {
	case .vet_tag:
		return(
			cfg.odin.explicit_allocators == .all ||
			(cfg.odin.explicit_allocators == .pure && (role == "pure" || role == "service")) \
		)
	case .banned_import:
		return role in cfg.dependencies
	case:
		return true
	}
}

advice_applies :: proc(t: ^Topic, role: string) -> bool {
	return len(t.applies_to.roles) == 0 || slice.contains(t.applies_to.roles, role)
}

scope_roles :: proc(roles: []string) -> string {
	names := make([dynamic]string, context.temp_allocator)
	for role in roles {append(&names, role if role != "" else "(unmapped)")}
	return strings.join(names[:], ", ", context.temp_allocator)
}

check_scope :: proc(cfg: ^Config, spec: ^Check_Spec) -> string {
	b := strings.builder_make(context.temp_allocator)
	if len(spec.roles) == 0 {
		strings.write_string(&b, "all roles, including unmapped packages")
	} else {
		fmt.sbprintf(&b, "roles %s", scope_roles(spec.roles))
	}
	if len(spec.except_roles) > 0 {fmt.sbprintf(&b, "; except %s", scope_roles(spec.except_roles))}
	#partial switch spec.kind {
	case .vet_tag:
		#partial switch cfg.odin.explicit_allocators {
		case .off:
			strings.write_string(&b, "; inactive: odin.explicit_allocators is off")
		case .pure:
			strings.write_string(
				&b,
				"; requires role pure or service under odin.explicit_allocators=pure",
			)
		case .all:
			strings.write_string(&b, "; odin.explicit_allocators=all")
		}
	case .banned_import:
		strings.write_string(&b, "; requires a dependencies policy for the package role")
	}
	return strings.to_string(b)
}

describe_rule :: proc(cfg: ^Config, topic: string, original: Rule) -> Rule {
	r := original
	r.scope = check_scope(cfg, &r.check)
	id := strings.concatenate({topic, "/", r.id}, context.temp_allocator)
	r.disabled_reason = cfg.disabled[id]
	return r
}

// Metadata scopes reviewer advice; each rule carries its own enforcement scope.
applicable_topics :: proc(p: ^Project, rels: []string, catalog := false) -> []Topic {
	out := make([dynamic]Topic)
	for original in p.rb.topics {
		t := original
		rules := make([dynamic]Rule)
		advice := catalog
		for rel in rels {
			role, _ := role_of(&p.cfg, rel)
			advice ||= advice_applies(&t, role)
		}
		for &r in t.rules {
			id := strings.concatenate({t.name, "/", r.id}, context.temp_allocator)
			if r.retired || id in p.cfg.disabled {continue}
			applies := catalog
			for rel in rels {
				role, _ := role_of(&p.cfg, rel)
				applies ||= check_applies(&p.cfg, r.check, role)
			}
			if applies {append(&rules, describe_rule(&p.cfg, t.name, r))}
		}
		t.rules = rules[:]
		if !advice {t.prose = ""; t.blocks = nil}
		if len(t.rules) > 0 || (advice && reader_checks(t) != "") {append(&out, t)}
	}
	return out[:]
}
