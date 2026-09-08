# The `@` expression resolves to an instance of Context.

Context <
	name: String                        # the scope's own name (nil for an anonymous scope)
	display_name: String                # name, or a richer form when tagged
	composed_types: Set                 # Set of every type it composes (own name + `|`/`&`/`~`/`^`)
	types: Array\String                 # "element" types -- Struct/Enum per-member list; composed_types otherwise
	type: Any                           # types[0] -- first member type (Struct), forced type (Enum), first composed type
	object_id: Number                   # Ruby's stable per-object id for this scope
	size_in_bytes: Integer              # shallow -- this scope object's own slot + buffers, not what it references
	root_path: String                   # the project root path (Tape::ROOT_PATH)
	static_declarations: Set            # Set of names declared static on this Type

	#- Func reflection
	parameters: Array
	arguments: Array
	func_signature: Any # todo; I don't have the Func_Signature type yet

	#- Struct reflection (nil unless the subject is a Struct)
	names: Array\String                 # member names
	type_names: Array\String            # member type names
	values: Array\Any                   # member values (also an Enum's member values)
	members: Array\Member               # Array of Member (needs the tapes/member.tape layer)

	#- Enum reflection (nil unless the subject is an Enum)
	keys: Array\String                  # member names
	count: Int                          # member count

	#- Functions (the interpreter binds an `@ruby` reference for each)
	to_s: (-> String;)                  # "@<name>" display
	puts: (Args -> Args;)               # prints each arg; passthrough (1 -> arg, 0 -> nil, N -> array)
	sleep: (Number;)                    # blocks for `seconds`
	assert: (Any, String;)              # raises Assert_Triggered unless the condition is truthy
	refute: (Any, String;)              # raises Refute_Triggered if the condition is truthy
	connect: (Database -> Database;)    # opens + caches a DB connection, returns the Database
	start_server: (Server -> Server;)   # boots the Server (background thread), returns it
	stop_server: (Server -> Server;)    # stops the Server, returns it

	#- Functions that act on the calling scope / the interpreter's scope stack -- run in the caller's frame
	load: (String;)                     # loads a .tape file into the current scope
	declare: (String, Any, Any;)        # declares an identifier in the current scope (name / name, value / name, value, type)
	push_scope: (Any;)                  # pushes a Type/Instance onto the stack -- members reachable unprefixed
	pop_scope: (Any;)                   # pops it back off (asserts identity with what push_scope pushed)
	splat: (Any;)                       # unpack a scope's members into lookup, also as a write target
	splatr: (Any;)                      # ... read-only
	unsplat: (Any;)                     # remove a splatted scope from lookup
>
