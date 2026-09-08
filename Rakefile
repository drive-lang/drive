require 'minitest/test_task'
require_relative 'drive/drive'
require 'pp'

task :default => [:test, :cloc]

Minitest::TestTask.create(:test) do |t|
	t.libs << 'tests'
	t.warning    = false
	t.test_globs = ['tests/**/*_test.rb']
end

task :cloc do
	sh "\ncloc --quiet --force-lang-def=drive.cloc --exclude-dir=.project,.working,.temporary,tests ."
end
