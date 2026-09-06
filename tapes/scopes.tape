# todo; write the Set and Dict variants

Scope <
	name: String
	enclosing_scope_reference: Scope
	readable_scopes: Set
	writable_scopes: Set
	declarations: Dict              # includes static
	static_declarations: Set\String # references what is static
	type_by_identifier: Dict
	tagged_type_variants: Dict\<String, Set>
>

declare (scope: Scope, identifier: String, value: Any, type: Any = nil -> Any;
	scope.declarations[identifier] = value
	scope.type_by_identifier[identifier] = type if type
	value
)

get (scope: Scope, key: String -> Any;
	return scope.declarations[key] if has?(scope, key)

	found := scope.writable_scopes.keys.reverse_each.find((it; it.has?(key) ))
	return scope.declarations[key] if found

	found := scope.readable_scopes.keys.reverse_each.find((it; it.has?(key) ))
	return scope.declarations[key] if found

	nil
)

has? (scope: Scope, key: String -> Bool;
	scope.declarations.key?(key)
)
