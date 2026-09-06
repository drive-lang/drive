@load 'tapes/any'
@load 'tapes/nil'
@load 'tapes/file_system'
@load 'tapes/date'
@load 'tapes/time'
@load 'tapes/date_time'
@load 'tapes/number'
@load 'tapes/array'
@load 'tapes/range'
@load 'tapes/set'
@load 'tapes/dictionary'
@load 'tapes/string'
@load 'tapes/symbol'
@load 'tapes/fence'
@load 'tapes/struct'
@load 'tapes/statement'
@load 'tapes/enum'
@load 'tapes/tuple'
@load 'tapes/bool'
@load 'tapes/context'

### How to load tapes.
@load 'tapes/some.tape'  # tapes/ is the stdlib found in ./tapes/
@load './this.tape'      # relative to wherever you ran bin/tape from (cwd)
@load 'that.tape'        # relative to wherever you ran bin/tape from (cwd)
@load 'and_this'         # no .tape extension required
###
