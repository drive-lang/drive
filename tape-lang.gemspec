require_relative 'src/version'

Gem::Specification.new do |spec|
	spec.name                  = 'tape-lang'
	spec.version               = Tape::VERSION
	spec.authors               = ['figgleforth']
	spec.summary               = 'Tape programming language'
	spec.description           = 'A programming language'
	spec.homepage              = 'https://github.com/figgleforth/tape-lang'
	spec.license               = 'MIT'
	spec.required_ruby_version = '>= 3.4.1'

	spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.start_with?('test/') }
	spec.bindir        = 'bin'
	spec.executables   = ['tape']
	spec.require_paths = ['src']

	spec.add_dependency 'webrick', '~> 1.9'
	spec.add_dependency 'listen', '~> 3.9'
	spec.add_dependency 'sequel', '~> 5.99'
	spec.add_dependency 'logger', '~> 1.7'
	spec.add_dependency 'sqlite3', '~> 2.9.0'
end
