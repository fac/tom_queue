require "yaml"

AMQP_CONFIG = YAML.load_file(APP_ROOT.join("config", "amqp.yml"))[APP_ENV]
