require 'minitest/autorun'
require_relative '../src/tape'
require_relative 'base_test'

class Lexer_Test < Base_Test
	def test_single_linecomment
		out = Tape.lex '# single line comment'
		assert_equal :comment, out.first.type
		assert_equal 'single line comment', out.first.value
		assert_kind_of Tape::Lexeme, out.first
	end

	def test_block_comment
		out = Tape.lex '###single line block comment###'
		assert_equal :comment, out.first.type
		assert_equal 'single line block comment', out.first.value
		assert_kind_of Tape::Lexeme, out.first

		out = Tape.lex '###multi
		line
		block
		comment###'
		assert_equal :comment, out.first.type
		assert out.first.value.start_with? 'multi'
		assert_kind_of Tape::Lexeme, out.first

		# a lone `#` or `##` inside a block comment's body shouldn't close it early -- only a real ### does
		out = Tape.lex "###\n# not a real comment\n## still not\n###"
		assert_equal :comment, out.first.type
		assert_equal 1, out.length

		# nesting: a same-length ### inside closes the outer block early, same as an unnested one would
		out = Tape.lex "###\nouter\n### inner ###\nouter again\n###"
		assert_equal :identifier, out[1].type # `inner` leaks out as real code
		assert_equal 'inner', out[1].value

		# a longer run of #s on the outer marker safely swallows a same-length (or shorter) ### inside, uncommenting nothing early
		out = Tape.lex "####\nouter\n### inner ###\nouter again\n####"
		assert_equal :comment, out.first.type
		assert_equal 1, out.length
		assert out.first.value.include? '### inner ###'
	end

	def test_fence_blocks
		out = Tape.lex '```single line fence block```'
		assert_equal :fence, out.first.type
		assert_equal 'single line fence block', out.first.value
		assert_kind_of Tape::Lexeme, out.first

		out = Tape.lex '```multi
		line
		fence
		block```'
		assert_equal :fence, out.first.type
		assert out.first.value.start_with? 'multi'
		assert_kind_of Tape::Lexeme, out.first

		# a longer run of backticks on the outer marker safely nests a same-length (or shorter) ``` inside, mirroring Markdown's own fence-nesting rule
		out = Tape.lex "`````\nouter\n```\ninner-looking, but shorter than the outer marker\n```\nouter again\n`````"
		assert_equal :fence, out.first.type
		assert_equal 1, out.length
		assert out.first.value.include? '```'
	end

	def test_identifiers
		tests = %w(lowercase UPPERCASE Capitalized).zip %I(identifier IDENTIFIER Identifier)
		tests.all? do |code, type|
			out = Tape.lex code
			assert_equal type, out.first.type
			assert_kind_of Tape::Lexeme, out.first
		end
	end

	def test_numbers
		assert_equal :number, Tape.lex('4').first.type
		assert_equal :number, Tape.lex('8.0').first.type
	end

	def test_prefixed_numbers
		out = Tape.lex '-15'
		assert_equal %I(number), out.map(&:type)
		assert_equal '-15', out.last.value # These are converted to numerical values once they become Number_Exprs
		assert_equal 1, out.count

		out = Tape.lex '+1.6'
		assert_equal %I(operator number), out.map(&:type)
		assert_equal '1.6', out.last.value
		assert_equal 2, out.count
	end

	def test_unusual_number_situations
		out = Tape.lex '20three'
		assert_equal %I(number identifier), out.map(&:type)
		assert_equal 2, out.count

		out = Tape.lex '40__two'
		assert_equal %I(number identifier), out.map(&:type)
		assert_equal 2, out.count

		out = Tape.lex '4_15_6_3_4'
		assert_equal :number, out.first.type
		assert_equal 1, out.count

		out = Tape.lex 'abc123'
		assert_equal :identifier, out.first.type
		assert_equal 1, out.count
	end

	def test_strings
		out = Tape.lex '"A string"'
		assert_equal :string, out.first.type

		out = Tape.lex "'Another string'"
		assert_equal :string, out.first.type

	end

	def test_interpolated_strings
		out = Tape.lex '"An `interpolated` string"'
		assert_equal :string, out.first.type

		out = Tape.lex "'Another `interpolated` string'"
		assert_equal :string, out.first.type
	end

	def test_unterminated_string_literal
		assert_raises Tape::Unterminated_String_Literal do
			Tape.lex '"test\\'
		end

		assert_raises Tape::Unterminated_String_Literal do
			Tape.lex "'test\\"
		end
	end

	def test_operators
		# todo Should this be such a long test?
		out = Tape.lex 'numbers += 4815162342'
		assert_equal %I(identifier operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex 'ENABLED = true'
		assert_equal %I(IDENTIFIER operator identifier), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex 'Type = {}'
		assert_equal %I(Identifier operator delimiter delimiter), out.map(&:type)
		assert_equal 4, out.count

		out = Tape.lex 'numbers,'
		assert_equal %I(identifier delimiter), out.map(&:type)
		assert_equal 2, out.count

		out = Tape.lex 'number: Number = 1'
		assert_equal %I(identifier operator Identifier operator number), out.map(&:type)
		assert_equal 5, out.count

		out = Tape.lex '1 + 2 * 3 / 4'
		assert_equal %I(number operator number operator number operator number), out.map(&:type)
		assert_equal 7, out.count

		out = Tape.lex '1 <=> 2'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex '1 == 2'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex '1 != 2'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex '1 > 2'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex '1 <= 2'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex '1...2'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex '3.0...4.0'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex '3..<4'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex '5>..6'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex '7>.<8'
		assert_equal %I(number operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex 'a, B, 5, "cool"'
		assert_equal %I(identifier delimiter IDENTIFIER delimiter number delimiter string), out.map(&:type)
		assert_equal 7, out.count

		out = Tape.lex '1...2, 3..<4, 5>..6, 7>.<8'
		assert_equal %I(number operator number delimiter number operator number delimiter number operator number delimiter number operator number), out.map(&:type)
		assert_equal 15, out.count

		out = Tape.lex './this_instance'
		assert_equal %I(operator identifier), out.map(&:type)
		assert_equal 2, out.count

		out = Tape.lex '../class_scope'
		assert_equal %I(operator identifier), out.map(&:type)
		assert_equal 2, out.count
	end

	def test_declaration_operators
		out = Tape.lex 'numbers := 4815162342' # This parses but I'm not using this any longer. Maybe I'll repurpose it.
		assert_equal %I(identifier operator number), out.map(&:type)
		assert_equal 3, out.count

		out = Tape.lex 'numbers = 123'
		assert_equal %I(identifier operator number), out.map(&:type)
		assert_equal 3, out.count
	end

	def test_functions
		out = Tape.lex '(;)'
		assert_equal [:delimiter, :delimiter, :delimiter], out.map(&:type)

		out = Tape.lex 'named_function (;)'
		assert_equal [:identifier, :delimiter, :delimiter, :delimiter], out.map(&:type)

		out = Tape.lex '( input; )'
		assert_equal [:delimiter, :identifier, :delimiter, :delimiter], out.map(&:type)

		out = Tape.lex '( labeled input; )'
		assert_equal [:delimiter, :identifier, :identifier, :delimiter, :delimiter], out.map(&:type)

		out = Tape.lex '( value := 123; )'
		assert_equal [:delimiter, :identifier, :operator, :number, :delimiter, :delimiter], out.map(&:type)

		out = Tape.lex '( labeled value := 123; )'
		assert_equal [:delimiter, :identifier, :identifier, :operator, :number, :delimiter, :delimiter], out.map(&:type)

		out = Tape.lex '( mixed, labeled value := 456; )'
		assert_equal [:delimiter, :identifier, :delimiter, :identifier, :identifier, :operator, :number, :delimiter, :delimiter], out.map(&:type)

		out = Tape.lex 'square ( input;
		 		input * input
		 	 )'
		assert_equal [
			             :identifier, :delimiter, :identifier, :delimiter, :delimiter,
			             :identifier, :operator, :identifier, :delimiter, :delimiter
		             ], out.map(&:type)

		out = Tape.lex 'wrap ( number, limit;
		 		if number > limit
		 			number = 0
		 		end
		 	 )'
		assert_equal [
			             :identifier, :delimiter, :identifier, :delimiter, :identifier, :delimiter, :delimiter,
			             :identifier, :identifier, :operator, :identifier, :delimiter,
			             :identifier, :operator, :number, :delimiter,
			             :identifier, :delimiter, :delimiter
		             ], out.map(&:type)
	end

	def test_types
		out = Tape.lex 'String {}'
		assert_equal [:Identifier, :delimiter, :delimiter], out.map(&:type)

		out = Tape.lex 'Transform {
		 	position,
		 	rotation,
		 }'
		assert_equal [
			             :Identifier, :delimiter, :delimiter,
			             :identifier, :delimiter, :delimiter,
			             :identifier, :delimiter, :delimiter,
			             :delimiter
		             ], out.map(&:type)

		out = Tape.lex 'Entity {
		 	|Transform
		}'
		assert_equal [
			             :Identifier, :delimiter, :delimiter,
			             :operator, :Identifier, :delimiter,
			             :delimiter
		             ], out.map(&:type)
	end

	def test_control_flow
		out = Tape.lex 'if true
			celebrate()
		end'
		assert_equal [
			             :identifier, :identifier, :delimiter,
			             :identifier, :delimiter, :delimiter, :delimiter,
			             :identifier
		             ], out.map(&:type)

		out = Tape.lex 'if 1 + 2 * 3 == 7
			"This one!"
		elif 1 + 2 * 3 == 9
			\'No, this one!\'
		else
			\'🤯\'
		end'
		assert_equal [
			             :identifier, :number, :operator, :number, :operator, :number, :operator, :number, :delimiter,
			             :string, :delimiter,
			             :identifier, :number, :operator, :number, :operator, :number, :operator, :number, :delimiter,
			             :string, :delimiter,
			             :identifier, :delimiter,
			             :string, :delimiter,
			             :identifier
		             ], out.map(&:type)

		out = Tape.lex 'for [1, 2, 3, 4, 5]
			remove it if randf() > 0.5
			skip
			stop
		end'
		assert_equal [
			             :operator, :delimiter, :number, :delimiter, :number, :delimiter, :number, :delimiter, :number, :delimiter, :number, :delimiter, :delimiter,
			             :identifier, :identifier, :identifier, :identifier, :delimiter, :delimiter, :operator, :number, :delimiter,
			             :operator, :delimiter,
			             :operator, :delimiter,
			             :identifier
		             ], out.map(&:type)
	end

	def test_compound_operators
		Tape::COMPOUND_OPERATORS.each do |operator|
			out = Tape.lex operator
			assert_equal operator, out.first.value
		end
	end

	def test_conditional_keywords
		out = Tape.lex 'and or'
		assert_equal :operator, out.first.type
		assert_equal :operator, out.last.type
	end

	def test_return_is_an_operator
		out = Tape.lex 'return 1 + 2'
		assert_equal :operator, out.first.type
	end

	def test_skip_and_stop_are_operators
		out = Tape.lex 'skip'
		assert_equal :operator, out.first.type

		out = Tape.lex 'stop'
		assert_equal :operator, out.first.type
	end

	def test_identifier_dot_integer
		out = Tape.lex 'array.0'
		assert_equal :identifier, out.first.type
		assert_equal 'array', out.first.value
		assert_equal :operator, out[1].type
		assert_equal '.', out[1].value
		assert_equal :number, out.last.type
		assert_equal '0', out.last.value
		# :lexeme_type_helper
	end

	def test_identifier_dot_float
		out = Tape.lex 'array.2.0'
		assert_equal :identifier, out.first.type
		assert_equal 'array', out.first.value
		assert_equal :operator, out[1].type
		assert_equal '.', out[1].value
		assert_equal :number, out.last.type
		assert_equal '2.0', out.last.value
		# :lexeme_type_helper
	end

	def test_number_with_multiple_decimal_points
		out = Tape.lex '1.2.3'
		assert_equal 1, out.count
		assert_equal :number, out.first.type
	end

	def test_double_less_than_is_operator
		out = Tape.lex '<<'
		assert_equal :operator, out.first.type
	end

	def test_at_at_prefix
		out = Tape.lex '@count'
		assert_equal :operator, out.first.type
	end

	def test_allowed_identifier_special_chars
		out = Tape.lex 'what?,'
		assert_equal :identifier, out.first.type
		assert_equal 'what?', out.first.value

		out = Tape.lex 'okay!,'
		assert_equal :identifier, out.first.type
		assert_equal 'okay!', out.first.value
	end

	def test_unpack_prefix
		out = Tape.lex '@instance_to_unpack'
		assert_equal :operator, out.first.type
		assert_equal Tape::BUILTIN_OPERATOR, out.first.value
		assert_equal :identifier, out.last.type
		assert_equal 'instance_to_unpack', out.last.value
	end

	def test_for_keyword
		out = Tape.lex 'for'
		assert_equal :operator, out.last.type
	end

	def test_single_line_code_location
		out = Tape.lex 'abracadabra'
		assert_equal 1, out.last.l0
		assert_equal 1, out.last.c0
		assert_equal 1, out.last.l1
		assert_equal 11, out.last.c1

		out = Tape.lex 'abracadabra = whatever'
		assert_equal 1, out.last.l0
		assert_equal 1, out.last.l1
		assert_equal 15, out.last.c0
		assert_equal 22, out.last.c1
	end

	def test_multiline_code_location
		out = Tape.lex <<~LEX
		    Thing {
		    	id,
		    	name,
		    }

		    for 1..2
		    	while true
		    		false until true
		    	end
		    end
		LEX
		assert_equal "1:1..1:5", out[0].line_col # Thing
		assert_equal "1:7..1:7", out[1].line_col # {
		assert_equal "1:8..2:1", out[2].line_col # \n
		assert_equal "2:2..2:3", out[3].line_col # id, Starts at column 2 because of indentation.
		assert_equal "2:4..2:4", out[4].line_col #;
		assert_equal "2:5..3:1", out[5].line_col # \n
		assert_equal "3:2..3:5", out[6].line_col # name
		assert_equal "3:6..3:6", out[7].line_col #;
		assert_equal "3:7..4:1", out[8].line_col # \n
		assert_equal "4:1..4:1", out[9].line_col # }

		assert_equal "4:2..5:1", out[10].line_col # \n
		assert_equal "5:1..6:1", out[11].line_col # \n

		assert_equal "6:1..6:3", out[12].line_col # \tfor
		assert_equal "6:5..6:5", out[13].line_col # 1
		assert_equal "6:6..6:7", out[14].line_col # ..
		assert_equal "6:8..6:8", out[15].line_col # 2
		assert_equal "6:9..7:1", out[16].line_col # \n
		assert_equal "7:2..7:6", out[17].line_col # \twhile
		assert_equal "7:8..7:11", out[18].line_col # true
		assert_equal "7:12..8:1", out[19].line_col # \n
		assert_equal "8:3..8:7", out[20].line_col # \t\tfalse
		assert_equal "8:9..8:13", out[21].line_col # until
		assert_equal "8:15..8:18", out[22].line_col # true
		assert_equal "8:19..9:1", out[23].line_col # \n
		assert_equal "9:2..9:4", out[24].line_col # end
		assert_equal "9:5..10:1", out[25].line_col # \n
		assert_equal "10:1..10:3", out[26].line_col # end
	end

	def test_debug
		Tape.lex '{ a=1, b="two", c=three }'
	end
end
