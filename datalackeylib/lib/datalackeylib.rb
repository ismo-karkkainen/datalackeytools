require 'json'
require 'open3'


class DatalackeyProcess
  attr_reader :exit_code, :stdout, :stderr, :stdin, :executable

  def initialize(exe, directory, permissions, memory)
    if exe.nil?
      exe = DatalackeyProcess.locate_executable(
        'datalackey', [ '/usr/local/libexec', '/usr/libexec' ])
      raise ArgumentError.new('datalackey not found') if exe.nil?
    elsif not File.exist?(exe) or not File.executable?(exe)
      raise ArgumentError.new("Executable not found or not executable: #{exe}")
    end
    @executable = exe
    args = [ exe,
        '--command-in', 'stdin', 'JSON', '--command-out', 'stdout', 'JSON' ]
    args.push('--memory') unless memory.nil?
    args.concat([ '--directory', directory ]) unless directory.nil?
    args.concat([ '--permissions', permissions ]) unless permissions.nil?
    @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*args)
  end

  def finish
    @stdin.close
    @wait_thread.join
    @exit_code = @wait_thread.value.exitstatus
  end
end

def DatalackeyProcess.locate_executable(exe_name, dirs_outside_path = [])
  # Absolute file name or found in current working directory.
  return exe_name if File.exist?(exe_name) and File.executable?(exe_name)
  dirs = []
  dirs_outside_path = [ dirs_outside_path ] unless dirs_outside_path.is_a? Array
  dirs.concat dirs_outside_path
  dirs.concat ENV['PATH'].split(File::PATH_SEPARATOR)
  dirs.each do |d|
    exe = File.join(d, exe_name)
    return exe if File.exist?(exe) and File.executable?(exe)
  end
  return nil
end

def DatalackeyProcess.verify_directory_permissions_memory(
    directory, permissions, memory)
  if not memory.nil? and not (directory.nil? and permissions.nil?)
    raise ArgumentError.new "Cannot use both memory and directory/permissions."
  end
  if memory.nil?
    if directory.nil?
      directory = Dir.pwd
    elsif not Dir.exist? directory
      raise ArgumentError.new "Given directory does not exist: #{directory}"
    end
    if permissions.nil?
      if (File.umask & 077) == 0
        permissions = '666'
      elsif (File.umask & 070) == 0
        permissions = '660'
      else
        permissions = "600"
      end
    elsif permissions != '600' and permission != '660' and permissions != '666'
      raise ArgumentError.new "Permissions not in {600, 660, 666}."
    end
  end
  return directory, permissions, memory
end


class DatalackeyParentProcess
  attr_reader :exit_code, :stdout, :stderr, :stdin, :executable

  def initialize(to_lackey, from_lackey)
    @exit_code = 0
    @stdout = from_lackey
    @stdin = to_lackey
    @stderr = nil
    @executable = nil
  end

  def finish
    @stdin.close
  end
end

CategoryAction = Struct.new(:category, :action)

class PatternAction
  @@generic_map = {
    :internal_error => [
      { :syntax => [ '@', 'error', 'missing', '*' ] },
      { :syntax => [ '@', 'error', 'not-string', '*' ] },
      { :syntax => [ '@', 'error', 'not-string-null', '*' ] },
      { :syntax => [ '@', 'error', 'pairless', '*' ] },
      { :syntax => [ '@', 'error', 'unexpected', '*' ] },
      { :syntax => [ '@', 'error', 'unknown', '*' ] },
      { :syntax => [ '@', 'error', 'command', 'missing', '?' ] },
      { :syntax => [ '@', 'error', 'command', 'not-string', '?' ] },
      { :syntax => [ '@', 'error', 'command', 'unknown', '?' ] },
      { :user_id => [ nil, 'error', 'identifier', '?' ] },
      { :format => [ nil, 'error', 'format' ] }
    ],
    :internal => [
      { :stored => [ nil, 'data', 'stored', '?', '?' ] },
      { :deleted => [ nil, 'data', 'deleted', '?', '?' ] },
      { :data_error => [ nil, 'data', 'error', '?', '?' ] },
      { :started => [ nil, 'process', 'started', '?', '?' ] },
      { :ended => [ nil, 'process', 'ended', '?', '?' ] },
      { :error_format => [ nil, 'error', 'format' ] },
      { :version => [ '@', 'version', "", '?' ] },
      { :done => [ '@', 'done', "" ] }
    ]
  }

  attr_reader :identifier
  attr_accessor :exit, :command, :status, :generators

  def initialize(action_maps_list, message_callables = [],
      identifier_placeholder = '@')
    @pattern2ca = { }
    @fixed2ca = { }
    @identifier = identifier_placeholder
    @exit = nil
    @command = nil
    @status = nil
    @generators = message_callables.is_a?(Array) ? message_callables.clone : [ message_callables ]
    maps = action_maps_list.clone
    maps.push @@generic_map
    maps.each do |ca2p|
      ca2p.each_pair do |category, action2pattern_list|
        action2pattern_list.each do |action2pattern|
          action2pattern.each_pair do |action, pattern|
            next unless pattern[0] == @identifier
            verified = []
            wildcards = false
            pattern.each do |item|
              verified.push item
              wildcards = (wildcards or item == '?' or item == '*')
              break if item == '*'
            end
            tgt = wildcards ? @pattern2ca : @fixed2ca
            tgt[verified] = [] unless tgt.has_key? verified
            tgt[verified].push CategoryAction.new(category, action)
          end
        end
        @pattern2ca.each_value { |ca| ca.uniq! }
      end
    end
  end

  def clone
    gens = @generators
    @generators = nil
    copy = Marshal.load(Marshal.dump(self))
    @generators = gens
    copy.generators = gens.clone
    return copy
  end

  def replace_identifier(identifier, p2ca)
    altered = { }
    p2ca.each_pair do |pattern, ca|
      p = []
      pattern.each { |item| p.push(item == @identifier ? identifier : item) }
      altered[p] = ca
    end
    return altered
  end

  def set_identifier(identifier)
    @pattern2ca = replace_identifier(identifier, @pattern2ca)
    @fixed2ca = replace_identifier(identifier, @fixed2ca)
    @identifier = identifier
  end

  def best_match(message_array)
    return [ @fixed2ca[message_array], [] ] if @fixed2ca.has_key? message_array
    best_length = 0
    best = nil
    best_vars = nil
    @pattern2ca.each_pair do |pattern, ca|
      next if message_array.length + 1 < pattern.length
      next if pattern.last != '*' and message_array.length != pattern.length
      length = 0
      exact_length = 0
      found = true
      vars = []
      pattern.each_index do |idx|
        if pattern[idx] == '*'
          vars.concat message_array[idx...message_array.length]
          break
        end
        if pattern[idx] == '?'
          vars.push message_array[idx]
          length += 1
          next
        end
        found = pattern[idx] == message_array[idx]
        break unless found
        exact_length += 1
      end
      next unless found
      if best_length < exact_length
        best_length = exact_length
        best = ca
        best_vars = vars
      elsif best_length < length
        best_length = length
        best = ca
        best_vars = vars
      end
    end
    return best, best_vars
  end
end


class DatalackeyIO
  attr_reader :syntax, :version

  def initialize(to_datalackey, from_datalackey, message_presenter_callable,
      notification_callable = nil,
      to_datalackey_echo_callable = nil, from_datalackey_echo_callable = nil)
    @to_datalackey_mutex = Mutex.new
    @to_datalackey = to_datalackey
    @to_datalackey_echo = to_datalackey_echo_callable
    @from_datalackey = from_datalackey
    @identifier = 0
    @tracked_mutex = Mutex.new
    @tracked = { nil => PatternAction.new([], [], nil) }
    @tracked.default = nil
    @waiting = nil
    @return_mutex = Mutex.new
    @return_condition = ConditionVariable.new
    @dataprocess_mutex = Mutex.new
    @data = Hash.new(0)
    @process = { }
    @version = { }
    @read_datalackey = Thread.new do
      accum = []
      while true do
        begin
          raw = @from_datalackey.readpartial(32768)
        rescue EOFError
          break
        end
        loc = raw.index("\n")
        until loc.nil? do
          accum.push(raw[0, loc]) if loc > 0 # Newline at start ends line.
          raw = raw[loc + 1, raw.length - loc - 1]
          loc = raw.index("\n")
          joined = accum.join
          accum.clear
          next if joined.empty?
          from_datalackey_echo_callable.call(joined) unless from_datalackey_echo_callable.nil?
          msg = JSON.parse joined
          # See if we are interested in it.
          tracker = @tracked_mutex.synchronize { @tracked[msg[0]] }
          next if tracker.nil?
          ca, vars = tracker.best_match(msg)
          next if ca.nil?
          if msg[0].nil?
            actionable = []
            ca.each do |item|
              case item.category.to_s
              when 'internal'
                name = vars.first
                id = vars.last
                # Messages from different threads may arrive out of order so
                # new data/process may be in book-keeping when previous should
                # be removed. With data these imply over-writing immediately,
                # with processes re-use of identifier and running back to back.
                case item.action.to_s
                when 'stored'
                  @dataprocess_mutex.synchronize do
                    if @data[name] < id
                      @data[name] = id
                      actionable.push item
                    end
                  end
                when 'deleted'
                  @dataprocess_mutex.synchronize do
                    if @data.has_key?(name) and @data[name] <= id
                      @data.delete name
                      actionable.push item
                    end
                  end
                when 'data_error'
                  @dataprocess_mutex.synchronize do
                    @data.delete(name) if @data[name] == id
                    actionable.push item
                  end
                when 'started'
                  @dataprocess_mutex.synchronize { @process[name] = id }
                  actionable.push item
                when 'ended'
                  @dataprocess_mutex.synchronize do
                    @process.delete(name) if @process[name] == id
                    actionable.push item
                  end
                when 'error_format'
                  @to_datalackey_mutex.synchronize { @to_datalackey.putc 0 }
                  actionable.push item
                end
              when 'internal_error'
                actionable.push item
              else
                next
              end
            end
            unless notification_callable.nil?
              actionable.each do |item|
                notification_callable.call(item.category, item.action, msg, vars)
              end
            end
            next # Notifications have been sent, no generators in nil tracker.
          end
          # Generate messages.
          msgs = []
          ca.each do |item|
            ms = []
            tracker.generators.each do |p|
              ms = p.call(item.category, item.action, msg, vars)
              break unless ms.empty?
            end
            msgs.concat ms
          end
          message_presenter_callable.call(msgs) unless message_presenter_callable.nil?
          next if msg[0] != @waiting
          # Check if the waited command needs to be finished etc.
          finish = false
          ca.each do |item|
            case item.category.to_s
            when 'return' then finish = true
            when 'error' then finish = true
            when 'internal'
              case item.action.to_s
              when 'done'
                finish = true
                @tracked_mutex.synchronize { @tracked.delete(msg[0]) }
              when 'version'
                @syntax = msg[3]['commands']
                @version = { }
                msg.last.each_pair do |key, value|
                  @version[key] = value if value.is_a? Integer
                end
              end
            end
          end
          if finish
            tracker.exit = ca
            @tracked_mutex.synchronize { @waiting = nil }
            @return_mutex.synchronize { @return_condition.signal }
          end
        end
        accum.push(raw) if raw.length > 0
      end
      @from_datalackey.close
      @return_mutex.synchronize { @return_condition.signal }
    end
    send(PatternAction.new([]), ['version'])
  end

  def data
    @dataprocess_mutex.synchronize { return @data.clone }
  end

  def process
    @dataprocess_mutex.synchronize { return @process.clone }
  end

  def closed?
    return @from_datalackey.closed?
  end

  def close
    @to_datalackey_mutex.synchronize { @to_datalackey.close }
  end

  def finish
    @read_datalackey.join
  end

  def send(pattern_action, command, user_id = false)
    return nil if @to_datalackey_mutex.synchronize { @to_datalackey.closed? }
    if user_id
      id = command[0]
    else
      id = @identifier
      @identifier += 1
      command.prepend id
    end
    tracker = pattern_action.clone
    tracker.set_identifier(id)
    tracker.command = JSON.generate(command)
    @tracked_mutex.synchronize {
      @tracked[id] = tracker unless id.nil?
      @waiting = id
    }
    dump(tracker.command)
    return tracker if id.nil? # There will be no responses.
    @return_mutex.synchronize { @return_condition.wait(@return_mutex) }
    tracker.status = true
    unless tracker.exit.nil?
      tracker.exit.each do |item|
        tracker.status = false if item.category == 'error'
      end
    end
    return tracker
  end

  def dump(json_as_string)
    @to_datalackey_mutex.synchronize {
      @to_datalackey.write json_as_string
      @to_datalackey.flush
      @to_datalackey_echo.call(json_as_string) unless @to_datalackey_echo.nil?
    }
  end

  def verify(command)
    return nil if @syntax.nil?
    return true
  end
end


class StoringReader
  def initialize(input)
    @input = input
    @output_mutex = Mutex.new
    @output = [] # Contains list of lines from input.
    @reader = Thread.new do
      accum = []
      while true do
        begin
          raw = @input.readpartial(32768)
        rescue EOFError
          break
        end
        loc = raw.index("\n")
        until loc.nil? do
          accum.push(raw[0, loc]) if loc > 0 # Newline begins?
          if accum.length
            @output_mutex.synchronize {
              @output.push(accum.join) if accum.length
            }
            accum.clear
          end
          raw = raw[loc + 1, raw.length - loc - 1]
          loc = raw.index("\n")
        end
        accum.push(raw) if raw.length > 0
      end
      @input.close
    end
  end

  def close
    @input.close
    @reader.join
  end

  def readlines
    @output_mutex.synchronize {
      result = @output
      @output = []
      return result
    }
  end
end


class DiscardReader
  def initialize(input)
    @input = input
    return if input.nil?
    @reader = Thread.new do
      while true do
        begin
          @input.readpartial(32768)
        rescue EOFError
          break
        end
      end
      @input.close
    end
  end

  def close
    return if @input.nil?
    @input.close
    @reader.join
  end

  def readlines
    return []
  end
end
