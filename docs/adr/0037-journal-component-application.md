# Journal each Component application

After authorization and before a Component's first mutation, Apply will atomically write a Secret-free pending journal, then verify effects before atomically committing ownership and clearing the journal. A later Plan only observes an interrupted journal: the next Apply may finalize a proven completed effect or resume idempotent convergence, while mismatched or ambiguous preconditions become blockers and package-manager effects are re-observed rather than rolled back.
