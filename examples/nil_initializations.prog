### Introduction

A trailing comma after a bare identifier declares it as `nil` -- shorthand for writing `identifier := nil` in full.
###
rescue_boat,
@assert rescue_boat == nil, 'a trailing comma should declare the identifier as nil'


### Same idiom inside a type body

Declaring a member this way inside a `Type { }` body works exactly the same -- one uninitialized member per instance, defaulting to `nil` until something sets it.
###
Raft {
	captain,
	crew,
}

r := Raft()
@assert r.captain == nil, 'an uninitialized member should default to nil'
@assert r.crew == nil, 'an uninitialized member should default to nil'


### A bare annotation self-declares too

`x: Number` with no `=` at all behaves the same way -- it's already self-declaring by virtue of the annotation, so it doesn't need `= nil` tacked on just to actually declare something. A bare struct annotation (`<...>`) works the same way.
###
altitude: Number
@assert altitude == nil, 'a bare type annotation with no value should self-declare to nil'

cargo: <String, Number>
@assert cargo == nil, 'a bare struct annotation with no value should self-declare to nil'
