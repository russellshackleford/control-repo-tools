# frozen_string_literal: true

require 'colorize'
require 'filemagic'

task default: [:help]

desc 'Display the list of available rake tasks'
task :help do
  system('rake -T')
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:rubocop) do |task|
    task.options = ['-D', '-S', '-E']
  end
rescue LoadError
  desc 'ERROR: rubocop missing'
  task :rubocop do
    raise 'ERROR: rubocop missing'
  end
end

desc 'Validate shell scripts in the files subdirectory'
task :shellcheck do
  puts 'Running shellcheck...'
  begin
    sh 'shellcheck --version >/dev/null', verbose: false
  rescue RuntimeError
    print 'shellcheck command not found! See '.red
    puts 'https://github.com/koalaman/shellcheck#installing to install it'.red
    raise
  end
  scripts = SortedSet.new
  Dir['**/*'].each do |file|
    mime = FileMagic.new(FileMagic::MAGIC_MIME).file(file)
    full = FileMagic.new(FileMagic::MAGIC_CONTINUE).file(file)
    scripts.add?(file) if file =~ /.sh$/
    scripts.add?(file) if mime =~ /x-shellscript/
    scripts.add?(file) if full =~ /(ba)?sh script/
  end
  sh "shellcheck #{scripts.to_a.join(' ')}" if scripts.count > 0
end

desc 'Run all tests'
task :precommit do
  Rake::Task[:shellcheck].invoke
  Rake::Task[:rubocop].invoke
end

# vim: set tw=80 ts=2 sw=2 sts=2 et:
