Gem::Specification.new do |s|
  s.name        = 'datalackeylib'
  s.version     = '0.0.1'
  s.date        = '2019-01-10'
  s.summary     = "Classes and methods for using datalackey."
  s.description = %q(
Classes and methods for using datalackey from Ruby programs.
Requires separately installed datalackey executable, installed into
/usr/local/libexec, /usr/libexec, or into a directory in $PATH.
)
  s.authors     = [ "Ismo Kärkkäinen" ]
  s.email       = 'ismokarkkainen@icloud.com'
  s.files       = [ "lib/datalackeylib.rb" ]
  s.homepage    = 'http://rubygems.org/gems/datalackeylib'
  s.license     = 'Nonstandard'
  s.add_runtime_dependency 'json', '~> 2.1', '>= 2.1.0'
end
