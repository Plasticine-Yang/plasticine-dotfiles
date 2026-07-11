# Git Reference Configuration

This directory is retained as Reference Configuration for manual inspection.
Runtime installation and drift handling belong to the `plasticine` Workstation
CLI Desired State, not to checkout-local shell snippets.

Personal Git Desired State must not include plaintext credential-store helpers.
Company Workstations can exclude `git-config`; when excluded, Plasticine does
not read, back up, or modify company-controlled Git configuration.
