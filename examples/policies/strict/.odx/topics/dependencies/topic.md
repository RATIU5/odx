---
name: "dependencies",
summary: "This application's domain source boundaries and explicit state",
applies_to: { roles: ["domain"] },
---

The application calls its roles domain, adapters, and app. Domain source has no
mutable package declarations or direct foreign syntax. Ordinary domain imports
obey the project's allow and transitive deny lists. Adapters can use OS facilities;
a domain import of such an adapter violates the domain's transitive boundary.
These are application choices, not Odin language requirements or proof of purity.
