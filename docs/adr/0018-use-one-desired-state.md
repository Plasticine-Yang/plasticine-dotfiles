---
status: superseded by ADR-0033
---

# Use one Desired State

Each Release will declare one Desired State for all of the Owner's Workstations, allowing explicit macOS and Debian/Ubuntu branches but no arbitrary profiles or persistent local overrides beyond Secret inputs. Component filtering may support diagnosis and retry without creating a second configuration; distinct machine roles will be introduced only if concrete divergence later justifies a small closed set.
