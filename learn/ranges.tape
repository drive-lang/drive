### Introduction

Four range operators, all built from the same `...` shape, differing only in whether the start and end are included. `...` is fully inclusive -- both ends stay in:
###
days := []
for 1...5
	days.push(it)
end
@assert days == [1, 2, 3, 4, 5], '... should include both ends'


### ..< excludes the end

Everything up to, but not including, the end:
###
days2 := []
for 1..<5
	days2.push(it)
end
@assert days2 == [1, 2, 3, 4], '..< should exclude the end'


### >.. excludes the start

Everything after the start, end included:
###
days3 := []
for 1>..5
	days3.push(it)
end
@assert days3 == [2, 3, 4, 5], '>.. should exclude the start'


### >.< excludes both ends

Neither the start nor the end is included -- only what's strictly between them:
###
days4 := []
for 1>.<5
	days4.push(it)
end
@assert days4 == [2, 3, 4], '>.< should exclude both ends'


### As a subscript -- slicing an Array or String

`xs[range]` takes a slice. Each operator keeps its own end behavior, so `[1...3]` (inclusive) is one
element longer than `[1..<3]`.
###
letters := [10, 20, 30, 40, 50]
@assert letters[1...3].values == [20, 30, 40].values, '[1...3] is inclusive -- indices 1, 2 and 3'
@assert letters[1..<3].values == [20, 30].values,     '[1..<3] stops before index 3'

@assert "abcdef"[0...2] == 'abc', 'string slices work the same way'
@assert "hello world"[6...11].upcase() == 'WORLD', 'and the slice is a real String you can chain off'

@assert [1, 2, 3][9...12] == nil, 'a start past the end is nil'


### Open-ended slices

Leave off either side and the range runs to that edge. A negative end counts back from the last
element, so `...-1` is the whole thing and `...-2` is everything but the last.
###
@assert letters[2...].values == [30, 40, 50].values, '[2...] runs from index 2 to the end'
@assert letters[...2].values == [10, 20, 30].values, '[...2] runs from the start to index 2'
@assert letters[...-1].values == letters.values,     '[...-1] is the whole array'
@assert letters[...-2].values == [10, 20, 30, 40].values, '[...-2] drops the last element'
@assert letters[1...-1].values == [20, 30, 40, 50].values, '[1...-1] -- index 1 through the last'
