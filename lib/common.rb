# frozen_string_literal: true

# Copyright © 2019-2021 Ismo Kärkkäinen
# Licensed under Universal Permissive License. See LICENSE.txt.

def aargh(message, exit_code = nil)
  $stderr.puts message
  exit(exit_code) unless exit_code.nil?
end
