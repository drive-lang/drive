module Lost
	class Dom_Renderer
		HTML_PREFIX  = 'html_'.freeze
		CSS_PREFIX   = 'css_'.freeze
		ELEMENT_ATTR = 'html_element'.freeze

		# Attributes whose mere presence is the "true" state -- rendered bare (`selected`), never
		# `selected="true"`. A false/nil value drops the attribute entirely (see #blank_attr_value?).
		BOOLEAN_ATTRS = %w[selected checked disabled readonly required multiple autofocus hidden open].freeze

		attr_accessor :dom, :element, :inner_html
		attr_accessor :onclick_token, :input_id_token
		attr_writer :html_attrs, :css_attrs

		def initialize dom_instance, inner_html = ''
			@dom        = dom_instance
			@element    = @dom.declarations[ELEMENT_ATTR]
			@inner_html = inner_html
		end

		def has_inner_html? # aka void tag
			!Lost::VOID_HTML_TAGS.include?(element)
		end

		# nil/false attribute values render nothing at all -- an unset `html_selected: Bool` (which
		# self-declares to nil) or an explicit `= false` drops the attribute instead of emitting
		# `selected=""`. `""` and `0` are real values and stay.
		def blank_attr_value? value
			value.nil? || value == false || (value.is_a?(Lost::Bool) && !value.truthiness)
		end

		def html_attrs
			@html_attrs ||= dom.declarations.reject do |key, _|
				# This identifier is just used to determine the element to render, so it shouldn't be included as an attribute of the final HTML string.
				key == 'html_element' || key == 'onclick'
			end.select do |key, value|
				key.to_s.start_with?(HTML_PREFIX) && !blank_attr_value?(value)
			end.map do |key, value|
				key = key.to_s.gsub HTML_PREFIX, ''
				key = key.gsub '_', '-'
				[key, value]
			end.to_h
		end

		def onclick_expr
			dom.declarations['onclick']
		end

		def is_input_element?
			%w[input textarea select].include? element
		end

		def css_attrs
			@css_attrs ||= dom.declarations.select do |key, value|
				key.to_s.start_with?(CSS_PREFIX) && !blank_attr_value?(value)
			end.map do |key, value|
				key = key.to_s.gsub CSS_PREFIX, ''
				key = key.gsub '_', '-'
				[key, value]
			end.to_h
		end

		def html_attrs_string
			html_attrs.map do |attr, value|
				bare = BOOLEAN_ATTRS.include?(attr) || true_value?(value)
				bare ? attr : "#{attr}=\"#{value}\""
			end.join(' ')
		end

		def true_value? value
			value == true || (value.is_a?(Lost::Bool) && value.truthiness)
		end

		def css_attrs_string
			css_attrs.map do |attr, value|
				"#{attr}:#{value}"
			end.join(';')
		end

		def to_html_string
			"<#{element}".tap do |html|
				unless html_attrs.empty?
					html << " "
					html << html_attrs_string
				end

				unless css_attrs.empty?
					html << " style=\""
					html << css_attrs_string
					html << "\""
				end

				if onclick_expr
					html << " data-lost-onclick=\"#{onclick_token}\""
				end

				if is_input_element?
					html << " data-lost-id=\"#{input_id_token}\""
				end

				html << ">"
				if has_inner_html?
					html << inner_html
					html << "</#{element}>"
				end
			end
		end
	end
end
