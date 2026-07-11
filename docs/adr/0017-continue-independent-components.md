# Continue independent Components after failure

Apply will guarantee atomicity within each Component where possible, skip Components whose dependencies fail, and continue Components on independent branches before returning a nonzero summary. It will not claim a global transaction or attempt unreliable rollback of package managers and other external systems; a later Apply observes actual state and resumes convergence.
