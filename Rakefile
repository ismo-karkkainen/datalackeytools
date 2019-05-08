task :default => [ :install ]

desc 'Install programs.'
task :install => [:installgem] do
  prefix = ENV.fetch('PREFIX', '/usr/local')
  [ 'datalackey-fsm', 'datalackey-make', 'datalackey-run', 'datalackey-shell' ].each do |exe|
    %x(sudo install #{exe} #{prefix}/bin/)
  end
end

desc 'Clean.'
task :clean do
  %x(rm -f datalackeylib/datalackeylib*.gem)
end

desc 'Build gem.'
task :build => [:clean] do
  Dir.chdir('datalackeylib') { %x(rake build) }
end

desc 'Build and install gem.'
task :installgem => [:build] do
  Dir.chdir('datalackeylib') { %x(rake install) }
end

desc 'Test gem.'
task :testgem do
  Dir.chdir('datalackeylib') { %x(rake test) }
end

desc 'Test'
task :test => [:testgem] do
  sh './test.sh'
end
