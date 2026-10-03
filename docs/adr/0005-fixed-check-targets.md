# The checker checks two fixed targets

The compiler checks only the files and `when` branches of one target, so the same commit gave different `odin` findings on macOS and Linux. odx now runs every compiler check for `darwin_arm64` and `linux_amd64`, whatever the host, and reports each finding once. Both targets check on macOS with no linker. There is no `targets` setting, because a per-project list would make each team's result a different standard (principle 1). macOS is the only host a release is tested on. Adding a target changes results, so it ships under a higher rule set.
