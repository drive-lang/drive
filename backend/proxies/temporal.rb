require 'date'
require 'time'

module Prog
	# Shared behavior for the three temporal wrappers Date / Time / DateTime
	module Temporal
		attr_accessor :value

		# Unwrap either a sibling temporal wrapper or a raw Ruby value.
		def raw_temporal other
			other.respond_to?(:value) ? other.value : other
		end

		def <=> other
			value <=> raw_temporal(other)
		end

		def < other
			(value <=> raw_temporal(other)) < 0
		end

		def > other
			(value <=> raw_temporal(other)) > 0
		end

		def <= other
			(value <=> raw_temporal(other)) <= 0
		end

		def >= other
			(value <=> raw_temporal(other)) >= 0
		end

		def == other
			value == raw_temporal(other)
		end

		def proxy_iso8601
			value.iso8601
		end

		def proxy_to_s
			value.iso8601
		end

		def proxy_year
			value.year
		end

		def proxy_month
			value.month
		end

		def proxy_day
			value.day
		end

		private

		# A string arg arrives raw (::String) for a literal, or as an Prog::String.
		def string_arg arg
			arg.respond_to?(:value) ? arg.value : arg.to_s
		end

		# A number arg arrives raw (Integer/Float) or as an Prog::Number (unwrap via proxy_value).
		def number_arg arg
			return arg.proxy_value if arg.respond_to?(:proxy_value)
			arg.respond_to?(:numerator) ? arg.numerator : arg
		end
	end

	# A calendar date — year, month, day. Wraps Ruby ::Date.
	class Date < Instance
		include Temporal

		def initialize value = ::Date.today
			super 'Date'
			@value = value.is_a?(::Date) ? value : ::Date.today
		end

		def proxy_today
			Prog::Date.new ::Date.today
		end

		def proxy_parse string
			Prog::Date.new ::Date.parse(string_arg(string))
		end

		def proxy_weekday
			value.wday
		end
	end

	# A wall-clock timestamp — date plus time of day plus epoch seconds. Wraps Ruby ::Time.
	class Time < Instance
		include Temporal

		def initialize value = ::Time.now
			super 'Time'
			@value = value.is_a?(::Time) ? value : ::Time.now
		end

		def proxy_now
			Prog::Time.new ::Time.now
		end

		def proxy_at epoch_seconds
			Prog::Time.new ::Time.at(number_arg(epoch_seconds))
		end

		def proxy_parse string
			Prog::Time.new ::Time.parse(string_arg(string))
		end

		def proxy_hour
			value.hour
		end

		def proxy_minute
			value.min
		end

		def proxy_second
			value.sec
		end

		def proxy_epoch
			value.to_i
		end
	end

	# A calendar-aware timestamp. Wraps Ruby ::DateTime — this is what a
	# `logged_at: Date_Time` table column maps to (see database.rb).
	class Date_Time < Instance
		include Temporal

		def initialize value = ::DateTime.now
			super 'Date_Time'
			@value = value.is_a?(::DateTime) ? value : ::DateTime.now
		end

		def proxy_now
			Prog::Date_Time.new ::DateTime.now
		end

		def proxy_parse string
			Prog::Date_Time.new ::DateTime.parse(string_arg(string))
		end

		def proxy_hour
			value.hour
		end

		def proxy_minute
			value.minute
		end

		def proxy_second
			value.second
		end
	end
end
