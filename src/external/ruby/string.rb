module Lost
	class String < Instance
		require 'digest/md5'
		extend Ruby_Proxies

		attr_accessor :value, :quotation_style

		def initialize value = "", quotation_style = nil
			super self.class.name
			@value                  = value
			@quotation_style        = quotation_style
			self['value']           = value
			self['quotation_style'] = quotation_style # a real Symbol (:single/:double), not stringified -- Array/Dictionary/Tuple/Member's to_s(;) all compare against it directly
		end

		proxy_delegate 'value'
		proxy :length
		proxy :ord
		proxy :upcase
		proxy :downcase
		proxy :slice!, as: :slice
		proxy :strip, as: :trim
		proxy :lstrip, as: :trim_left
		proxy :rstrip, as: :trim_right
		proxy :index
		proxy :to_i
		proxy :to_f
		proxy :empty?
		proxy :include?
		proxy :reverse
		proxy :replace
		proxy :start_with?
		proxy :end_with?
		proxy :gsub

		def proxy_to_md5_hash
			Digest::MD5.hexdigest value
		end

		def proxy_split * args
			Lost::Array.new value.split(*args)
		end

		def proxy_chars
			Lost::Array.new value.chars
		end

		def + other
			value + other.value
		end

		def * other
			value * other
		end

		def == other
			value == (other.is_a?(Lost::String) ? other.value : other)
		end

		# Closes the direction the `==` fix above couldn't reach on its own: a raw Ruby ::String on the *left* of `==`  invokes Ruby's own native String#==, not this class's, but Ruby's own implementation already special-cases exactly this: if the right-hand object isn't a String but responds to #to_str, it delegates the comparison to `object == self` instead, which lands right back on Lost::String#== above.
		def to_str
			value
		end
	end

	class Fence < String
	end
end
