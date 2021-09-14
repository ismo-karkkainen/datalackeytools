# frozen_string_literal: true

task default: [:install]

desc 'Clean.'
task :clean do
  `rm -f datalackeytools-*.gem`
end

desc 'Build gem.'
task build: [:clean] do
  `gem build datalackeytools.gemspec`
end

desc 'Build and install gem.'
task install: [:build] do
  `gem install datalackeytools-*.gem`
end

desc 'Test gem library.'
task :testgem do
  sh 'test/test_process'
  sh 'test/test_patternaction'
  sh 'test/test_io'
end

desc 'Test.'
task test: %i[testgem testmake teststate testrun testio] do
end

desc 'Test make.'
task testmake: [:testgem] do
  sh './test.sh make'
end

desc 'Test state.'
task teststate: [:testgem] do
  sh './test.sh state'
end

desc 'Test run.'
task testrun: [:testgem] do
  sh './test.sh run'
end

desc 'Test file io.'
task testio: [] do
  sh './test.sh io'
  sh './test.sh object'
end
