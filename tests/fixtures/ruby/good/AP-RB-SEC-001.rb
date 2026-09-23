# ok: slopguard.ruby.eval-user-input
ALLOWED_FORMULAS = { 'sum' => ->(a, b) { a + b }, 'max' => ->(a, b) { [a, b].max } }.freeze

def run_formula(name, a, b)
  fn = ALLOWED_FORMULAS.fetch(name) { raise ArgumentError, "Unknown formula" }
  fn.call(a, b)
end

# ok: slopguard.ruby.send-user-input
ALLOWED_ACTIONS = %w[approve reject archive].freeze

def call_action(obj, action_name)
  raise ArgumentError unless ALLOWED_ACTIONS.include?(action_name)
  obj.public_send(action_name)
end
