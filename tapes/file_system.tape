File_System {
	Self.read ( filepath -> String;
		read_file_to_string(filepath)
	)

	Self.read_file_to_string ( filepath -> String;
		@ruby
	)

	Self.write_string_to_file ( filepath, string;
		@ruby
	)
}

read_file_to_string ( path: String -> String;
	File_System.read_file_to_string(path)
)

### todo;

# File system operations - flat procedures, no class wrappers, no indirection.

# file.tape
# Reads an entire file into a string buffer.
# Returns empty string if reading fails.
read_entire_file ( path: String -> String;
    @ruby # or native syscall wrapper, interpreter should use file name (file in this case) as the external Ruby backing for this file. I think we should allow backing entire files with Ruby, leaving out the class name entirely on the Drive side. A person can then `space := @load '...'` to namespace file.tape.
)

# Writes a string buffer directly to disk.
# Returns status code/bool instead of silently swallowing outcomes.
write_string_to_file ( path: String, contents: String -> Bool;
    @ruby # or native syscall wrapper
)

###
