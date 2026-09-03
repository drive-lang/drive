### Introduction

`@push_scope <Type or instance>` pushes that scope directly onto the stack, so declarations made inside it become real members of the target -- unlike readable/writable scopes (see learn/readable_scopes.tape, learn/writable_scopes.tape), which only add a fallback lookup place without mutating anything. `@pop_scope <same target>` pops back out to whatever scope was active before -- it asserts the target is identical to what `@push_scope` actually pushed, raising instead of popping the wrong thing.
###
Button {
	label := 'default'
}

@push_scope Button
	css_filter := 'invert()'
@pop_scope Button

b := Button()
@assert b.css_filter == 'invert()', 'a member declared while pushed onto the Type should be reachable on an instance'


### Reopening a Type extends every instance

`css_filter` above was added to the `Button` type, not to any one instance -- so every `Button()` built afterward (and even ones already built) sees it, the same as if it had been declared in the original body:
###
another_button := Button()
@assert another_button.css_filter == 'invert()', 'the same declaration should be shared by every Button'


### Reopening one instance changes just that instance

`@push_scope` also accepts an instance directly, in which case the new declarations land only on that one value -- every other instance of the same type is untouched:
###
c := Button()
d := Button()

@push_scope c
	onclick := 'clicked'
@pop_scope c

@assert c.onclick == 'clicked', 'the reopened instance should have the new member'
# d.onclick would raise Tape::Undeclared_Identifier -- only c was reopened, not the Button type
