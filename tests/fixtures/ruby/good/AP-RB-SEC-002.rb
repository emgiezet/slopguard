# ok: slopguard.ruby.constantize-user-input
ALLOWED_MODELS = { 'user' => User, 'post' => Post, 'comment' => Comment }.freeze

def build_model(model_name)
  klass = ALLOWED_MODELS.fetch(model_name) { raise ArgumentError, "Unknown model" }
  klass.new
end
