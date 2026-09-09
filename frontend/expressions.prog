# todo; write Array\Expression and so on

# Enums
Http_Method [GET PUT PATCH POST DELETE HEAD OPTIONS CONNECT TRACE]
Percent_Literal_Type [str Str STR string sym Sym SYM symbol] # turns out this works too, not just ALL CAPS
Literal_Type [STRING SYMBOL NUMBER FENCE HTML]
Fixity [PREFIX POSTFIX INFIX CIRCUMFIX]
Quotation_Style [SINGLE DOUBLE]
Privacy [PUBLIC PRIVATE]
Binding [INSTANCE STATIC]

# Structs
Anylike | Expression <>
Numberlike | Expression <>
Html_Fence | Fencelike <>
Nil_Init | Infix <>

Code_Location <
	source_file: String # or maybe we should add Path?

	line_range: Range
	char_range: Range

	line_start: Int
	line_end: Int
	char_start: Int
	char_end: Int
>

Lexeme <
	type: Any
	value: Any
	reserved: Bool
	quotation_style: Quotation_Style
	location: Code_Location
>

Expression <
	lexemes: Array\Lexeme
	value: Any
>

Param | Expression <
	name: String
	label: String
	type: Any
	default: Any
	add_to_readable: Bool
	add_to_writable: Bool
>

Func | Expression <
	name: String
	body: Array\Expression
	parameters: Array\Param
	signature: Func_Signature
>

Route | Func <
	http_method: Http_Method
	path: String,
	expression: Expression
	param_names: Array\String
>

Func_Signature | Expression <
	name: String
	params: Array\Param
	signature: String
>

Directive | Expression <
	name: String
	expression: Expression
	message: String # used for @assert and @refute
	arguments: Array
>

Structure | Expression < # todo; call this Struct, rename intrinsic to Structure to match full word like siblings.
	types: Array\Any
	names: Array\String
	declared_name: String
>

Enum | Expression <
	name: String
	type: Any
	expressions: Array\Expression
>

Type | Expression <
	name: String
	expressions: Array\Expression
	tag: Any
	anonymous_composition: Bool
	struct_body: Structure # this should not be on Type, it belongs with Structure
>

Stringlike | Expression <
	interpolated: Bool
	quotation_style: Quotation_Style
>

Prefix | Expression <
	operator: Lexeme
	expression: Expression
>

Postfix | Expression <
	operator: Lexeme
	expression: Expression
>

Infix | Expression <
	operator: Lexeme
	left: Expression
	right: Expression
>

Circumfix | Expression <
	grouping: String
	expressions: Array\Expression
>

Percent_Literal | Circumfix <
	type: Percent_Literal_Type
>

Operator | Expression <
	precedence: Int
>

Operator_Overload | Operator <
	func_expr: Func
	fixity: Fixity
>

Identifier | Expression <
	kind: Any
	directive: Bool
	scope_operator: String
	privacy: Privacy
	binding: Binding
	tag: Any
	member_default: Any # todo; call it `default`
>

Composition | Expression <
	operator: Operator
	identifier: Identifier
>

Conditional | Expression <
	condition: Expression
	when_true: Array\Expression
	when_false: Array\Expression
>

Call | Expression <
	receiver: Expression
	arguments: Array\Expression
>

Subscript | Expression <
	receiver: Expression
	expression: Expression
>

Array_Index | Expression <
	indices_in_order: Array\Int
>

For_Loop | Expression <
	collection: Array
	stride: Int
	body: Array\Expression
>

Fencelike | Expression <
	header: String
	body: String
>

Statement | Expression <
	expression: Expression
>

Comment | Expression  <
	body: String
>
