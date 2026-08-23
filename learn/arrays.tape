### Introduction

Arrays are created with `[]`. Backed by `Lost::Array`, a thin wrapper around a real Ruby array kept in `.values`. Elements are reachable by subscript or by dot notation -- both just index into the same underlying array.
###
raft_supplies := ['water', 'rope', 'tarp']
@assert raft_supplies.0 == 'water', 'dot notation should index like subscript'
@assert raft_supplies[0] == 'water', 'subscript should index the first element'


### push and pop

`push` adds to the end, `pop` removes from the end and returns what it removed.
###
raft_supplies.push('flare')
@assert raft_supplies == ['water', 'rope', 'tarp', 'flare'], 'push should append to the end'
@assert raft_supplies.pop() == 'flare', 'pop should return what it removed'
@assert raft_supplies == ['water', 'rope', 'tarp'], 'pop should remove from the end'


### length, first, last, reverse

###
@assert raft_supplies.length() == 3, 'length should count the elements'
@assert raft_supplies.first(2) == ['water', 'rope'], 'first(2) should take from the front'
@assert raft_supplies.last(2) == ['rope', 'tarp'], 'last(2) should take from the back'
@assert raft_supplies.reverse() == ['tarp', 'rope', 'water'], 'reverse should flip the order'


### include? and empty?

###
@assert raft_supplies.include?('rope') == true, 'include? should find a present element'
@assert raft_supplies.empty?() == false, 'a non-empty array should not report empty?'
@assert [].empty?() == true, 'an empty array should report empty?'


### map and filter

Both take a function and run it against every element -- `map` collects each return value, `filter` keeps only elements the function returns truthy for.
###
survivors := ['Jack', 'Kate', 'Sawyer', 'Hurley']

shouted := survivors.map(( name;
	name.upcase()
))
@assert shouted == ['JACK', 'KATE', 'SAWYER', 'HURLEY'], 'map should collect each return value'

long_names := survivors.filter(( name;
	name.length > 4
))
@assert long_names == ['Sawyer', 'Hurley'], 'filter should keep only truthy elements'
