# ok: slopguard.ruby.shell-injection-interpolation
def delete_file(filename)
  # Array form avoids shell interpolation
  system("rm", "-f", filename)
end
