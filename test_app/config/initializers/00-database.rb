require "yaml"
require "active_record"

ActiveRecord::Base.raise_in_transactional_callbacks = true

settings = YAML.load_file(APP_ROOT.join("config", "database.yml"))[APP_ENV]
ActiveRecord::Base.establish_connection(settings)
