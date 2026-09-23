# ruleid: slopguard.ruby.constantize-user-input
def build_model(model_name)
  model_name.constantize.new
end
