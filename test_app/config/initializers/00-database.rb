require "yaml"

settings = YAML.load_file(APP_ROOT.join("config", "database.yml"))[APP_ENV]
ActiveRecord::Base.establish_connection(settings)
