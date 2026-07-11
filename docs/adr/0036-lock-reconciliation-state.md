# Lock Reconciliation State across each command

Plan and Doctor will hold a shared process lock, while Apply and Bootstrap version replacement hold an exclusive lock for their complete operation and fail fast with holder information on contention. The lock prevents `plasticine` processes from racing each other but not external edits, so every planned mutation still checks its observed precondition digest and reports a stale Plan instead of overwriting changed state.
