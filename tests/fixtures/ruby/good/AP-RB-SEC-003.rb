require 'yaml'

# ok: slopguard.ruby.yaml-load-unsafe
def load_config(yaml_string)
  YAML.safe_load(yaml_string, permitted_classes: [Symbol])
end
