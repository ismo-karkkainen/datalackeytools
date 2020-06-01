task :default => [ :install ]

desc 'Install programs to PREFIX/bin.'
task :install => [:installgem] do
  prefix = ENV.fetch('PREFIX', '/usr/local')
  target = File.join(prefix, 'bin')
  puts "Using PREFIX #{prefix} to install to #{target}."
  abort("Target #{target} is not a directory.") unless File.directory? target
  [ 'datalackey-fsm', 'datalackey-make', 'datalackey-run', 'datalackey-shell', 'files2mapped', 'input2mapped' ].each do |exe|
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
task :test => [:testgem] do
  sh './test.sh'
end
