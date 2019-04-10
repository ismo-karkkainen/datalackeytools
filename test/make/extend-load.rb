
class ExtensionCommand < Command
  def initialize
    super('extension')
  end

  def handle(cmd)
    cmd.flatten!
    if cmd.length == 1
      userout "No parameters."
      return true
    end
    userout "Extension: #{cmd[1...cmd.length].join(' ')}"
    return true
  end
end

