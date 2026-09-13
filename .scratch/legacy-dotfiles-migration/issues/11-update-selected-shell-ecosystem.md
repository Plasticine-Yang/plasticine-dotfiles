# 11: Update the selected shell ecosystem through native mechanisms

**What to build:** Make each selected shell apply bring Antidote, Powerlevel10k, and the shell plugin ecosystem to their current native upstream targets, while preserving the existing Zsh system/APT policy and Owner customization. A successful shell installation must include the requested native updates and a usable runtime.

**Blocked by:** 07 — Separate tool preparation from configuration effects.

**Status:** done

- [ ] Retain the existing independently selectable shell interface and reviewed installation routes. Zsh remains a healthy system installation or is prepared through the existing APT route; it is not forced to the newest upstream release.
- [ ] Check and update an existing Antidote through its positively identified permitted native owner rather than accepting health alone. Refresh native metadata for Homebrew-backed updates and update only the selected formula, never all packages.
- [ ] Use the current upstream target for native checkout routes without introducing a fixed tag, commit, Tool Lock, or versioned launcher. Unknown ownership, unhealthy installations, conflicting local checkout changes, and failed native updates receive guidance instead of forced resets, takeovers, or fallback routes.
- [ ] Update Powerlevel10k and the shell plugin ecosystem through Antidote's native operations on each selected apply. A satisfied upstream target must not cause unnecessary replacement or managed-configuration backup, while an upstream change must be observed on the next invocation.
- [ ] Preserve the Owner-controlled optional plugin declarations and all content outside the selected shell Integration Block. Native updater changes to plugin checkouts and generated state are allowed, but Base Dotfiles must not adopt, relocate, copy from legacy, or clean that state.
- [ ] Run configuration-dependent native operations using the intended selected configuration and native plugin locations, without sourcing unrelated Owner startup code merely to perform installation. Existing and optional plugin declarations retain their native semantics.
- [ ] Keep selected route planning and local validation before mutation, executable preparation before managed configuration, configuration-dependent plugin updates before final readiness, and mode restoration before the login-shell transition.
- [ ] A failed currency lookup, Antidote update, plugin synchronization, or runtime readiness check returns failure. Report any already-applied configuration or native updates accurately and allow a retry; do not report success just because an older shell environment can start.
- [ ] Preview and cancellation do not query latest upstream targets or update the shell ecosystem. Unselected shell state is not probed or mutated by feature-specific work, and non-interactive confirmation never supplies native Homebrew, sudo, or login-shell credentials.
- [ ] Preserve guarded fnm activation, later Owner code execution, local plugin extensibility, existing PATH defaults, and the behavior of runtime warnings. Updating the shell ecosystem does not implicitly install or upgrade fnm or Node.
- [ ] Use controlled Homebrew, checkout, plugin-manager, and platform fixtures to test missing/older/current targets, metadata failure, native update failure, local-change refusal, partial plugin failure, retry, and selected-only isolation through public entrypoints.
- [ ] Use real Zsh in disposable homes to verify successful startup with updated plugin fixtures, Powerlevel10k availability, fnm activation failure handling, local plugin loading, later Owner overrides, and combined Lazygit alias behavior. Do not make real network or host package-manager calls in automated tests.
- [ ] Update usage documentation to explain the Zsh exception, shell-ecosystem currency, native state ownership, privilege requirements, and failure/retry behavior. Keep relevant installer, integration, runtime, and release regressions passing within this slice.
