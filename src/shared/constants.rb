module Tape
	DOM_CONSTRUCTOR_PROP_NAMES        = %w(onclick key)
	DOM_CONSTRUCTOR_PROP_PREFIXES     = %w(html_ css_)
	HTML_ATTRS                        = %w(id class href)
	HTTP_VERBS                        = %w(get put patch post delete head options connect trace)
	VOID_HTML_TAGS                    = %w(area base br col command embed hr img input keygen link meta param source track wbr)
	HTTP_VERB_SEPARATOR               = '://'
	CONTEXT_FUNCTIONS                 = %w(to_s puts sleep assert refute connect start_server stop_server load push_scope pop_scope declare add_readable_scope add_writable_scope remove_readable_scope remove_writable_scope add_readable add_writable remove_readable remove_writable readable writable)
	CONTEXT_STACK_FUNCTIONS           = %w(load push_scope pop_scope declare add_readable_scope add_writable_scope remove_readable_scope remove_writable_scope add_readable add_writable remove_readable remove_writable readable writable)
	CONTEXT_SCOPE_FUNCTION_ALIASES    = {
		                                    'readable'        => 'add_readable_scope', 'add_readable' => 'add_readable_scope',
		                                    'writable'        => 'add_writable_scope', 'add_writable' => 'add_writable_scope',
		                                    'remove_readable' => 'remove_readable_scope', 'remove_writable' => 'remove_writable_scope',
	                                    }
	CONTEXT_OPERATOR                  = '@'
	CONTEXT_ARG_TERMINATORS           = %W( \n \r \) \} \] \, \; )
	NIL_INIT_POSTFIX                  = ','
	FUNCTION_DELIMITER                = ';'
	PERCENT_LITERALS                  = %w(string symbol str Str STR sym Sym SYM)
	FOR_VERBS                         = %w(each map select reject count)
	BROWSER_VIEW_SIZE                 = 'browser_view_size'
	INTERPOLATE_CHAR                  = '`' # easily distinguishable betwen ```
	COMMENT_CHAR                      = '#'
	BLOCK_COMMENT_CHARS               = '###'
	FENCE_CHARS                       = '```'
	PREFIX                            = %w(! - + ~ not return)
	INFIX                             = %w( + - ^ * ** / % ~ == === =!= =>= =<= =/= ? . .? = := : ||= &&= **= <<= >>= += -= *= |= /= %= &= ^= =~ !~ && || & | << >>
 ... >.. ..< >.< != <= >= < > <=> < > and or )
	POSTFIX                           = %w() # note: ; can never be a postfix, it's reserved
	CIRCUMFIX                         = %w( \( [ { | )
	CIRCUMFIX_GROUPINGS               = { '(' => '()', '{' => '{}', '[' => '[]', '|' => '||' }
	LOGICAL_OPERATORS                 = %w(&& & || | and or)
	COMPOUND_OPERATORS                = %w(||= &&= **= <<= >>= += -= *= |= /= %= &= ^=)
	COMPARISON_OPERATORS              = %w(<=> == === =!= =>= =<= =/= != <= >= < > =~ !~)
	ANY_WILDCARD_COMPARISON_OPERATORS = %w(== != === =!= =>= =<= =/=)
	INFIX_ARITHMETIC_OPERATORS        = %w(+ - * ** / % << >> ^ & |)
	RANGE_OPERATORS                   = %w(... ..< >.. >.<)
	SCOPE_OPERATORS                   = %w(~/)
	SELF_KEYWORDS                     = %w(self Self)
	DOT_ACCESS_OPERATORS              = %w(. .?)
	TAG_OPERATOR                      = '\\'
	TYPE_COMPOSITION_OPERATORS        = %w(| & ~ ^) # Union, Intersection, Removal, Symmetric Difference
	ANY_IDENTIFIER                    = %i(identifier Identifier IDENTIFIER)
	TYPE_IDENTIFIER                   = %i(Identifier IDENTIFIER)
	GSCOPE                            = :global
	STARTING_PRECEDENCE               = 0
	DEFAULT_OPERATOR_PRECEDENCE       = 500 # given to all custom operators at runtime unless
	DELIMITERS                        = %W(, ; { } ( ) [ ] \n \r)
	ILLEGAL_OPERATOR_CHARS            = %w(` ' " { } ( ) [ ] , ; )
	NEWLINES                          = %W(\r\n \n \r)
	WHITESPACES                       = %W(\t \s)
	NUMERIC_REGEX                     = /\A\d+\z/
	ALPHA_REGEX                       = /\A\p{Alpha}+\z/
	ALPHANUMERIC_REGEX                = /\A\p{Alnum}+\z/
	SYMBOLIC_REGEX                    = /\A[^\p{Alnum}\s]+\z/

	# It's been a while, but I believe this RESERVED list must be maintained. The other declarations above are helpers for comparisons while this contains every reserved symbols and identifiers.
	RESERVED = %w(
		[ { ( , _ . .? .. ) } ]
		: ; + - * ** / % ~
		= := ||= &&= **= <<= >>= += -= *= |= /= %= &= ^=
		== != <= >= < > === =!= =/= =<= =>=
		! ? ?? !! && || & | << >>
		... >.. ..< >.< <=>
		``` # \
		@ ~/

		if elif elsif else
		while elwhile elswhile
		unless until
		and or return
		true false nil
		skip stop
		self Self
		for
	)

	PRECEDENCES = {
		              # Member access
		              '.' => 1200, '.?' => 1200,

		              # Subscript/call
		              '[' => 1100, '{' => 1100, '(' => 1100,

		              # Exponentiation
		              '**' => 1000,

		              # Unary
		              '!' => 900, 'not' => 900, '\\' => 900,

		              # Multiplicative
		              '*' => 800, '/' => 800, '%' => 800,

		              # Additive
		              '+' => 700, '-' => 700,

		              # Bitwise shifts
		              '<<' => 600, '>>' => 600,

		              # Relational
		              '<' => 550, '<=' => 550, '<=>' => 550, '>' => 550, '>=' => 550,

		              # Type set comparison
		              '=>=' => 550, '=<=' => 550, '=!=' => 500, '=/=' => 500,

		              # Equality
		              '==' => 500, '!=' => 500, '===' => 500,

		              # Bitwise AND
		              '&' => 450,

		              # Bitwise XOR
		              '^' => 425,

		              # Bitwise OR
		              '|' => 410,

		              # Logical AND
		              '&&' => 300, 'and' => 300,

		              # Logical OR
		              '||' => 200, 'or' => 200,

		              # Member/label
		              ':' => 140,

		              # Comma
		              ',' => 100,

		              # Assignment
		              '='   => 90, ':=' => 90, '+=' => 90, '-=' => 90, '*=' => 90, '/=' => 90,
		              '%='  => 90, '&=' => 90, '&&=' => 90, '|=' => 90, '||=' => 90,
		              '^='  => 90, '<<=' => 90, '>>=' => 90,
		              '**=' => 90,

		              # Ranges
		              '...' => 80, '..<' => 80, '>..' => 80, '>.<' => 80,

		              # Keywords
		              'return' => 70,
		              'unless' => 60, 'if' => 60, 'while' => 60, 'until' => 60,
	              }
end
