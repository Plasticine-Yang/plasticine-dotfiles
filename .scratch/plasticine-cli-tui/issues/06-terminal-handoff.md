# 06 — Hand the controlling terminal to system commands safely

Status: implemented

- [x] Introduce a terminal-command value and runner seam for apt, Apple tools,
  login-shell changes, and other controlling-terminal processes.
- [x] Suspend Bubble Tea rendering while a command owns the terminal and resume
  the alternate screen afterward.
- [x] Propagate command failure and Owner-action status back to Apply.
- [x] Make authorization, key selection, and command handshakes context-aware
  without leaked goroutines or raw terminal state.

## Comments
