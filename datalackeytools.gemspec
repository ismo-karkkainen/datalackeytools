Gem::Specification.new do |s|
  s.name        = 'datalackeytools'
  s.version     = '0.3.0'
  s.date        = '2021-09-14'
  s.summary     = "Tools for using datalackey."
  s.description = %q(
Tools for using datalackey.
Requires separately installed datalackey executable, installed into
/usr/local/libexec, /usr/libexec, or into a directory in $PATH.

Licensed under Universal Permissive License, see License.txt.
)
  s.authors     = [ 'Ismo Kärkkäinen' ]
  s.email       = 'ismokarkkainen@icloud.com'
  s.files       = [ 'lib/datalackeylib.rb' ]
  s.executables << 'datalackey-make'
  s.executables << 'datalackey-run'
  s.executables << 'datalackey-shell'
  s.executables << 'datalackey-state'
  s.executables << 'files2object'
  s.executables << 'object2files'
  s.homepage    = 'http://rubygems.org/gems/datalackeytools'
  s.license     = 'Nonstandard'
  s.add_runtime_dependency 'json', '~> 2.1', '>= 2.1.0'
end
