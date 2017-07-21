# These extensions allow properly serializing and autoloading of
# Classes, Modules and Structs

require 'yaml'
if YAML.parser.class.name =~ /syck|yecht/i
  require File.expand_path('../serialization/syck_ext', __FILE__)
  require File.expand_path('../serialization/active_record', __FILE__)
else
  require File.expand_path('../serialization/psych_ext', __FILE__)
end
