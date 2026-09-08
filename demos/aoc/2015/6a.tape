### Day 6: Probably a Fire Hazard
Because your neighbors keep defeating you in the holiday house decorating contest year after year, you've decided to deploy one million lights in a 1000x1000 grid.

Furthermore, because you've been especially nice this year, Santa has mailed you instructions on how to display the ideal lighting configuration.

Lights in your grid are numbered from 0 to 999 in each direction; the lights at each corner are at 0,0, 0,999, 999,999, and 999,0. The instructions include whether to turn on, turn off, or toggle various inclusive ranges given as coordinate pairs. Each coordinate pair represents opposite corners of a rectangle, inclusive; a coordinate pair like 0,0 through 2,2 therefore refers to 9 lights in a 3x3 square. The lights all start turned off.

To defeat your neighbors this year, all you have to do is set up your lights by doing the instructions Santa sent you in order.

For example:
- turn on 0,0 through 999,999 would turn on (or leave on) every light.
- toggle 0,0 through 999,0 would toggle the first line of 1000 lights, turning off the ones that were on, and turning on the ones that were off.
- turn off 499,499 through 500,500 would turn off (or leave off) the middle four lights.

After following the instructions, how many lights are lit?
###

@load 'tapes/file_system'

INPUT := read_file_to_string('demos/aoc/2015/6a.txt').split("\n")

Vec2 <x: Int, y: Int>
Instruction <command: String, subcommand: String, from: Vec2, till: Vec2>

instructions := INPUT.map(line;
	parts := line.split_by_spaces()
	inst := Instruction()

	# 0: Command
	inst.command = parts.0

	# 1: Subcommand
	if %str(on off).include?(parts.1)
		inst.subcommand = String(parts.1)
	else
		# This must be toggle so it has no subcommand. Insert a fake element at 2, to align the other parts of toggle's line
		parts.insert(1, nil)
	end

	# 2: Corner One
	coords := parts.2.split(',').map(it; it.to_i() )
	inst.from = Vec2(coords.0, coords.1)

	# 4: Corner Two
	coords = parts.4.split(',').map(it; it.to_i() )
	inst.till = Vec2(coords.0, coords.1)

	@assert inst.from.x <= inst.till.x and inst.from.y <= inst.till.y

	inst
)

GRID_SIZE := 1000
grid := Array.new(GRID_SIZE * GRID_SIZE, false)

# ~20M cells across the 300 instructions, so the inner loop stays flat: a plain index (y*W + x)
# and a direct grid write, no per-cell Vec2 / helper-call.
instructions.each(@splatr inst: Instruction;
	toggle := inst.command == 'toggle'
	on     := inst.subcommand == 'on'

	@assert toggle or inst.command == 'turn', "idk this command: `inst.command`"
	@assert toggle or on or inst.subcommand == 'off', "idk this subcommand: `inst.subcommand`"

	for inst.from.y...inst.till.y
		row := it * GRID_SIZE
		for inst.from.x...inst.till.x
			i := row + it
			if toggle
				grid[i] = !grid[i]
			else
				grid[i] = on
			end
		end
	end
)

@puts tally(grid, true)

tally (@splatr array: Array, value: Any -> Int;
	total := 0
	for values
		total += 1 if it == value
	end
	total
)

#   0|    1|      2|      3|      4|
#    |     |       |       |       |
#    v     v       v       v       v
# turn   off 150,300 through 213,740
# turn   on  141,242 through 932,871
# toggle *** 294,259 through 474,326
#      |   |       |       |       |
#     0|  1|      2|      3|      4|
#         ^--- the element we'll insert on `toggle` to preserve the pattern
