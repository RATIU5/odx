package odx

import "core:odin/ast"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

// One plugin script whose behaviour is chosen by the MODE file next to it, so every failure
// class the host promises to catch is exercised against a real subprocess.
@(test)
test_plugins :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator // ponytail: the CLI never frees; the leak checker would
	defer free_all(context.temp_allocator)
	root, _ := os.make_directory_temp("", "odx-plugin-test-*", context.allocator)
	root = canonical(root)
	defer os.remove_all(root)
	os.make_directory_all(join({root, ".odx", "plugins"}))
	exe := join({root, ".odx", "plugins", "odx-demo"})
	mode := join({root, "MODE"})
	script := strings.concatenate(
		{
			"#!/bin/sh\ncat >/dev/null\ncase \"$(cat ",
			mode,
			")\" in\n",
			"ok) echo '{\"protocol\":1,\"checks\":[\"demo/R1\"],\"violations\":[{\"file\":\"a.odin\",\"line\":3,\"col\":0,\"rule\":\"demo/R1\",\"message\":\"nope\"}]}';;\n",
			"proto) echo '{\"protocol\":2,\"checks\":[\"demo/R1\"]}';;\n",
			"none) echo '{\"protocol\":1,\"checks\":[]}';;\n",
			"shadow) echo '{\"protocol\":1,\"checks\":[\"errors/R1\"]}';;\n",
			"outside) echo '{\"protocol\":1,\"checks\":[\"demo/R1\"],\"violations\":[{\"file\":\"../x.odin\",\"rule\":\"demo/R1\"}]}';;\n",
			"foreign) echo '{\"protocol\":1,\"checks\":[\"demo/R1\"],\"violations\":[{\"file\":\"a.odin\",\"rule\":\"odx/stale-ignore\"}]}';;\n",
			"garbage) echo 'not json';;\n",
			"crash) echo boom; exit 3;;\n",
			"hang) sleep 5;;\n",
			"esac\n",
		},
	)
	_ = os.write_entire_file(exe, transmute([]byte)script)
	_ = os.chmod(exe, os.Permissions_Read_Write_All + os.Permissions_Execute_All)

	cfg: Config
	cfg.plugins["demo"] = sha256_hex(transmute([]byte)script)
	rb: Rulebook
	append(&rb.topics, Topic{name = "errors"})
	f := ast.File {
		fullpath = join({root, "a.odin"}),
	}
	pkgs := []Package{{files = {&f}}}
	plugin_timeout = 200 * time.Millisecond

	run :: proc(cfg: ^Config, rb: ^Rulebook, pkgs: []Package, root, mode, m: string) -> Report {
		_ = os.write_entire_file(mode, m)
		r: Report
		c := Ctx {
			root = root,
			cfg  = cfg,
			rb   = rb,
			pkgs = pkgs,
			r    = &r,
		}
		run_plugins(&c)
		return r
	}

	r := run(&cfg, &rb, pkgs, root, mode, "ok")
	testing.expect_value(t, len(r.tool_errors), 0)
	if testing.expect_value(t, len(r.violations), 1) {
		v := r.violations[0]
		testing.expect(
			t,
			v.rule == "demo/R1" &&
			v.file == "a.odin" &&
			v.line == 3 &&
			v.col == 1 &&
			v.check == "plugin:demo" &&
			!v.ignorable,
			v.message,
		)
	}

	// every failure class is one tool error and zero violations
	Case :: struct {
		mode, want: string,
	}
	for c in ([]Case{{"proto", "protocol 2"}, {"none", "declares no checks"}, {"shadow", "shadows a rulebook topic"}, {"outside", "did not scan"}, {"foreign", "not one of its declared checks"}, {"garbage", "unparseable"}, {"crash", "exited 3"}, {"hang", "timed out"}}) {
		r = run(&cfg, &rb, pkgs, root, mode, c.mode)
		testing.expectf(
			t,
			len(r.violations) == 0,
			"%s: leaked %d violations",
			c.mode,
			len(r.violations),
		)
		if testing.expectf(t, len(r.tool_errors) == 1, "%s: %v", c.mode, r.tool_errors[:]) {
			testing.expectf(
				t,
				strings.contains(r.tool_errors[0], c.want),
				"%s: %s",
				c.mode,
				r.tool_errors[0],
			)
		}
	}

	cfg.plugins["demo"] = "deadbeef"
	r = run(&cfg, &rb, pkgs, root, mode, "ok")
	testing.expect(
		t,
		len(r.tool_errors) == 1 && strings.contains(r.tool_errors[0], "sha256 mismatch"),
	)
	delete_key(&cfg.plugins, "demo")
	cfg.plugins["ghost"] = "00"
	r = run(&cfg, &rb, pkgs, root, mode, "ok")
	testing.expect(t, len(r.tool_errors) == 1 && strings.contains(r.tool_errors[0], "not found"))
}
