Gem::Specification.new do |s|
  s.name        = 'datalackeylib'
  s.version     = '0.2.0'
  s.date        = '2019-03-16'
  s.summary     = "Classes and methods for using datalackey."
  s.description = %q(
Classes and methods for using datalackey from Ruby programs.
Requires separately installed datalackey executable, installed into
/usr/local/libexec, /usr/libexec, or into a directory in $PATH.

Licensed under Universal Permissive License, see License.txt.
)
  s.authors     = [ "Ismo Kärkkäinen" ]
  s.email       = 'ismokarkkainen@icloud.com'
  s.files       = [ "lib/datalackeylib.rb" ]
  s.homepage    = 'http://rubygems.org/gems/datalackeylib'
  s.license     = 'Nonstandard'
  s.add_runtime_dependency 'json', '~> 2.1', '>= 2.1.0'
end
