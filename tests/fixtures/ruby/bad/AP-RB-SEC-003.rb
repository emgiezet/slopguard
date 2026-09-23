require 'yaml'

# ruleid: slopguard.ruby.yaml-load-unsafe
def load_config(yaml_string)
  YAML.load(yaml_string)
end
