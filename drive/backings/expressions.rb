module Disk
	class Expression
		attr_accessor :lexemes # the entire span of lexemes that make up this expression

		attr_accessor :value, :type, :l0, :c0, :l1, :c1, :source_file
		attr_reader :lexeme # todo; this should become #lexeme that returns @lexemes.first

		def initialize lexeme = nil
			self.lexeme = lexeme
		end

		def lexeme= lexeme
			case lexeme
			when Disk::Lexeme
				@value  = lexeme.value
				@lexeme = lexeme
			when ::String, ::Symbol
				@value  = lexeme
				@lexeme = Disk::Lexeme.new Helpers.type_identifier?(lexeme), lexeme
			end
		end

		# note; this was a stupid idea
		def is compare
			if compare.is_a? Symbol
				compare == type
			elsif compare.is_a? ::String
				compare == value
			elsif compare.is_a? Class
				self.is_a? compare
			else
				compare == self
			end
		end

		def isnt compare
			is(compare) == false
		end

		def location
			return nil unless l0 && c0
			"#{source_file}:#{l0}:#{c0}" if source_file
			"#{l0}:#{c0}"
		end

		def line_col
			"#{l0}:#{c0}..#{l1}:#{c1}" if l0
		end
	end

	class Param_Expr < Expression
		attr_accessor :name, :label, :type, :default, :add_to_readable, :add_to_writable, :variadic
	end

	class Func_Expr < Expression
		attr_accessor :name, :expressions, :signature, :parameters

		def signature
			sig = name&.value || ''
			sig += '('
			sig += parameters.map do |param|
				label   = param.label ? "#{param.label.value}:" : ''
				default = param.default ? "=#{param.default.value}" : ''
				"#{label}#{param.name.value}#{default}"
			end.join(',')
			sig += Disk::FUNCTION_DELIMITER
			sig += ')'
			sig
		end
	end

	# get:// (;)
	# put://whatever/:id (id;)
	# post://book/:id/publish (id;)
	class Route_Expr < Func_Expr
		attr_accessor :http_method, :path, :expression, :param_names # The expression can be a function or an identifier
	end

	class Func_Signature_Expr < Expression
		attr_accessor :signature, :params, :name
	end


	class Struct_Expr < Expression
		attr_accessor :types, :names # names[i] is nil for unnamed members, e.g. `Type<String>` but has value for named members, e.g. `Type<str: String>`
		attr_accessor :name # the type name this struct was parsed after, e.g. `Named` in `Named<String, Number>` -- nil for an anonymous struct (`<String, Number>` with nothing preceding it)

		def to_s
			::String.new("<").tap do |str|
				types.zip(names).each_with_index do |it, at|
					type = it[0]
					name = it[1] # Optional, may be nil

					# For a named member (`s: String`), `type` is the whole Identifier_Expr
					# (`.value` is the name "s", already captured in `name`) -- the actual
					# type annotation lives on its `.type` Lexeme instead. An unnamed member can
					# be any expression, not just a bare type-name identifier (`Abc<'users'>`,
					# `Abc<1+2+3>`, ...) -- every Expression subtype carries a `.value` off its
					# own lexeme via the shared base, even if it's not a perfect rendering of
					# a compound expression; `.inspect` is the last-resort fallback for
					# anything that isn't an Expression at all, so this never raises.
					type = if name && type.type
						type.type.value
					elsif name && type.respond_to?(:member_default) && type.member_default
						# A named member with no `: Type` annotation (`done := false`) has no `.type` to read -- fall back to rendering its default value instead.
						type.member_default.value
					elsif type.respond_to? :value
						type.value
					else
						type.inspect
					end

					str << if name
						"#{name}: #{type}"
					else
						type.to_s
					end
					str << "," unless at == types.length - 1
				end

				str << ">"
			end
		end
	end

	class Enum_Expr < Expression
		attr_accessor :name, :type, :expressions
	end

	class Type_Expr < Expression
		attr_accessor :name, :expressions, :tag
		# A bare composition chain (`Abc|Def`), no `{}` body -- an anonymous type reference, not a declaration.
		attr_accessor :anonymous_composition
		# A trailing `<...>` (instead of `{...}`) after a composition chain (`Both | Abc | Def <extra: String>`) -- a Struct_Expr holding this declaration's own extra members, merged in on top of whatever the chain composes. Struct-flavored sibling of a `{}` body; nil for an ordinary type declaration/composition.
		attr_accessor :struct_body
	end

	class Number_Expr < Expression
		# Useful reading.
		# https://stackoverflow.com/a/18533211/1426880
		# https://stackoverflow.com/a/1235891/1426880
	end

	class Symbol_Expr < Expression
		def initialize lexeme
			super lexeme
			@value = @value.to_s.to_sym
		end
	end

	class String_Expr < Expression
		STYLES = %i(single double).freeze
		attr_accessor :interpolated, :quotation_style

		def initialize lexeme
			super lexeme
			@interpolated    = value.to_s.include? INTERPOLATE_CHAR
			@quotation_style = lexeme.respond_to?(:quotation_style) ? lexeme.quotation_style : nil
		end
	end

	class Prefix_Expr < Expression
		attr_accessor :operator, :expression
	end

	class Postfix_Expr < Expression
		attr_accessor :operator, :expression
	end

	# :operator, :left, :right
	class Infix_Expr < Expression
		attr_accessor :operator, :left, :right
	end

	class Circumfix_Expr < Expression
		attr_accessor :grouping, :expressions
	end

	class Percent_Literal_Expr < Circumfix_Expr
		# The kind of the literal. (str, string, sym, symbol)
		attr_accessor :kind # :grouping, :expressions
		# %string(boo Hoo) -> ['boo', 'Hoo'] # preserves yours
		# %str(Boo HOO)    -> ['boo', 'hoo'] # forces lowercase
		# %Str(boo HOO)    -> ['Boo', 'Hoo'] # forces Capitalcase
		# %STR(boo Hoo)    -> ['BOO', 'HOO'] # forces UPPERCASE
		#
		# %symbol(BOO hoo) -> [:BOO, :hoo]   # preserves yours
		# %sym(Boo HOO)    -> [:boo, :hoo]   # forces lowercase
		# %Sym(boo HOO)    -> [:Boo, :Hoo]   # forces Capitalcase
		# %SYM(boo hHo)    -> [:BOO, :HOO]   # forces UPPERCASE
	end

	class Nil_Init_Expr < Infix_Expr
	end

	class Operator_Expr < Expression
		attr_accessor :precedence
	end

	class Operator_Overload_Expr < Expression
		attr_accessor :func_expr, :fixity, :precedence
	end

	class Identifier_Expr < Expression
		attr_accessor :kind, :scope_operator, :prefixed_with_at, :privacy, :binding, :tag, :member_default
	end

	class Composition_Expr < Expression
		attr_accessor :operator, :identifier
	end

	class Conditional_Expr < Expression
		attr_accessor :condition, :when_true, :when_false
	end

	class Call_Expr < Expression
		attr_accessor :receiver, :arguments
	end

	class Subscript_Expr < Expression
		attr_accessor :receiver, :expression
	end

	class Array_Index_Expr < Expression
		attr_accessor :indices_in_order
	end

	class For_Loop_Expr < Expression
		attr_accessor :collection, :stride, :body
	end

	class Fence_Expr < Expression
		attr_accessor :header
		# ```header
		# ```
		# Examples are md, css, html, disk, etc
	end

	class Statement_Expr < Expression
		attr_accessor :expression
		# x := `<expr>`
		# x() to evaluate it
	end

	class Comment_Expr < Expression
		attr_accessor :body
	end

	class Html_Fence_Expr < Expression
		# ```html
		# ```
		attr_accessor :body, :element
	end
end
