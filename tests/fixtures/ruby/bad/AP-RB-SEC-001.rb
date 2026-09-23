# ruleid: slopguard.ruby.eval-user-input
def run_formula(user_code)
  eval(user_code)
end

# ruleid: slopguard.ruby.send-user-input
def call_action(obj, action_name)
  obj.send(action_name)
end
