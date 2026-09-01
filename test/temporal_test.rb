require 'minitest/autorun'
require_relative '../src/lost'
require_relative 'base_test'

class Temporal_Test < Base_Test
	def test_date_today_is_a_date
		assert_equal Time.now.year, Lost.interp('Date.today().year')
	end

	def test_date_parse_reads_components
		out = Lost.interp('d := Date.parse("2020-03-15"), [d.year, d.month, d.day]')
		assert_equal [2020, 3, 15], out.values
	end

	def test_date_weekday
		# 2020-03-15 is a Sunday
		assert_equal 0, Lost.interp('Date.parse("2020-03-15").weekday')
	end

	def test_date_iso8601
		assert_equal '2020-03-15', Lost.interp('Date.parse("2020-03-15").iso8601()')
	end

	def test_date_comparison
		assert_equal true, Lost.interp('Date.parse("2020-01-01") < Date.parse("2021-01-01")')
		assert_equal false, Lost.interp('Date.parse("2021-01-01") < Date.parse("2020-01-01")')
		assert_equal true, Lost.interp('Date.parse("2020-06-01") == Date.parse("2020-06-01")')
		assert_equal true, Lost.interp('Date.parse("2020-06-02") != Date.parse("2020-06-01")')
	end

	def test_time_now_and_epoch
		assert_equal true, Lost.interp('Time.now().epoch() > 1500000000')
	end

	def test_time_at_epoch_zero
		# Wall-clock year depends on the machine's zone (1970 at/east of UTC, 1969 west of it), so
		# assert on the epoch round-trip instead -- that's zone-independent.
		out = Lost.interp('t := Time.at(0), [t.epoch(), t.year]')
		assert_equal 0, out.values[0]
		assert_includes [1969, 1970], out.values[1]
	end

	def test_date_time_now_components
		out = Lost.interp('dt := Date_Time.now(), [dt.year >= 2026, dt.month >= 1, dt.hour >= 0]')
		assert_equal [true, true, true], out.values
	end

	def test_date_time_parse_and_iso8601
		out = Lost.interp('Date_Time.parse("2020-03-15T09:30:00+00:00").iso8601()')
		assert_equal '2020-03-15T09:30:00+00:00', out
	end

	def test_date_time_comparison
		code = <<~TAPE
		    a := Date_Time.parse("2020-01-01T00:00:00+00:00")
		    b := Date_Time.parse("2020-01-01T00:00:01+00:00")
		    [a < b, a <= a, b > a, a == a]
		TAPE
		assert_equal [true, true, true, true], Lost.interp(code).values
	end

	def test_date_time_round_trips_through_a_table_column
		filepath = "./temp_temporal_test_#{Process.pid}.db"
		File.delete(filepath) if File.exist?(filepath)

		code = <<~TAPE
		    @load 'lost/database.tape'
		    @load 'lost/table.tape'
		    db := @connect Sqlite('#{filepath}')

		    Log_Schema <
		        id: Primary_Key
		        note: String
		        logged_at: Date_Time
		    >
		    table := db.find_or_create_table(Log_Schema)
		    table.create(<note := "old", logged_at := Date_Time.parse("2000-01-01T00:00:00+00:00")>)
		    table.create(<note := "new", logged_at := Date_Time.now()>)

		    old := table.all().0
		    fresh := table.all().1
		    [old.note, old.logged_at.year, old.logged_at < fresh.logged_at]
		TAPE

		out = Lost.interp(code)
		assert_equal 'old', out.values[0]
		assert_equal 2000, out.values[1]
		assert_equal true, out.values[2]
	ensure
		File.delete(filepath) if filepath && File.exist?(filepath)
	end
end
