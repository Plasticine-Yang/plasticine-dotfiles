# Use Apply for first and later runs

Bootstrap will invoke the same Apply operation that the Owner uses for every later Reconciliation. An empty Workstation, a drifted Workstation, and an already converged Workstation are merely different observed states, so there will be no separate initialization path whose behavior or tests can diverge from repeat execution.
