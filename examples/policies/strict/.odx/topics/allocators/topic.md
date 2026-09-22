---
name: "allocators",
summary: "Domain files opt into the compiler's explicit-allocator directive",
applies_to: { roles: ["domain"] },
---

Only domain files require the directive. The project's all setting enables the
matcher for custom roles; the rule's domain filter selects the actual files.

## Reader checks

### Is ownership clear to callers?

Document who retains or frees returned memory. Caller-owned arenas are legitimate;
a matching defer statement does not prove lifetime correctness. Neither this
advice nor the directive establishes allocation freedom.
