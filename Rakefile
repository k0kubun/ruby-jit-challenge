require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  #t.ruby_opts = %w[-rtest_helper]
  t.test_files = %w[test/jit/*_test.rb]
  t.verbose = true
end

task default: :test
