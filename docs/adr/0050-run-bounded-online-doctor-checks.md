# Run bounded online checks in Doctor

Doctor will combine local diagnostics with short-timeout HTTPS reachability and, when `github-ssh` is active, a non-interactive BatchMode GitHub SSH authentication check. Checks never prompt, change known hosts, or perform remote writes and continue independently after failures; network health affects Doctor's exit status but never makes offline Plan perform I/O.
