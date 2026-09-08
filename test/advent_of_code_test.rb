require 'minitest/autorun'
require_relative '../drive/drive'
require_relative 'base_test'

# The Advent of Code solutions in learn/aoc/ crunch real puzzle input and are slow (day 4 brute-forces
# MD5, day 6 touches ~20M grid cells), so they don't run in a normal `rake test`. Each file ends in an
# `answer == expected` expression, so `interp_file` returning truthy = solved.
#
#   AOC=1 rake test          -- run them
#   AOC=1 ruby test/advent_of_code_test.rb
#
# As more days get solved (and as the language gets faster), un-comment / add lines below.
class Advent_Of_Code_Test < Base_Test
	SOLVED = %w[
		1a 1b
		2a 2b
		3a 3b
		4a 4b
		5a 5b
		6a
	].freeze

	SOLVED.each do |day|
		define_method "test_2015_#{day}" do
			assert Drive.interp_file("learn/aoc/2015/#{day}.tape"),
			       "learn/aoc/2015/#{day}.tape did not return a truthy answer check"
		end
	end

	remove_method(*SOLVED.map { |d| :"test_2015_#{d}" }) unless ENV['AOC']
end
