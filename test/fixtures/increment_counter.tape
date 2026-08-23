# Regression fixture: bare @load into the same scope should only run this file once, even if @load'd
# more than once -- see test_double_load_into_same_scope_only_runs_once in regression_test.rb.
# Mutates the caller's own `counter` (merged into the same scope by bare @load) so a second run is
# observable, and returns it too, so the *result* of a second, deduped @load can be checked as well.
counter += 1
counter
