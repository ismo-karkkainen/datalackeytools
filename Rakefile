task :default => [ :install ]

desc 'Install programs to PREFIX/bin.'
task :install => [:installgem] do
  prefix = ENV.fetch('PREFIX', '/usr/local')
  target = File.join(prefix, 'bin')
  puts "Using PREFIX #{prefix} to install to #{target}."
  abort("Target #{target} is not a directory.") unless File.directory? target
  [ 'datalackey-state', 'datalackey-make', 'datalackey-run', 'datalackey-shell', 'files2object', 'object2files' ].each do |exe|
    puts "Installing #{exe}."
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

desc 'Test.'
task :test => [:testgem, :testmake, :teststate, :testrun, :testio] do
end

desc 'Test make.'
task :testmake => [:testgem] do
  sh './test.sh make'
end

desc 'Test state.'
task :teststate => [:testgem] do
  sh './test.sh state'
end

desc 'Test run.'
task :testrun => [:testgem] do
  sh './test.sh run'
end

desc 'Test file io.'
task :testio => [] do
  sh './test.sh io'
  sh './test.sh object'
end
