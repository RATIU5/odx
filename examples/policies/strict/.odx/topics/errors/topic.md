---
name: "errors",
summary: "Domain result acknowledgement for two chosen failure-name suffixes",
applies_to: { roles: ["domain"] },
---

Domain APIs selected by canonical final-result name suffix must carry
@(require_results). Optional unions and status enums are not classified structurally.

## Reader checks

### Is explicit discard intentional?

The compiler permits assigning results to `_`. Review whether the caller should
recover, propagate, or deliberately discard them; attribute presence does not
prove meaningful handling.
