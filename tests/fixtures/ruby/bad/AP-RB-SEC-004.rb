# ruleid: slopguard.ruby.shell-injection-interpolation
def delete_file(filename)
  system("rm -f #{filename}")
end
