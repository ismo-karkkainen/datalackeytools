
# Licensed under Universal Permissive License. See LICENSE.txt.

require 'json'
require 'open3'

class DatalackeyProcess
  attr_reader :exit_code, :stdout, :stderr, :stdin, :executable

  def initialize(exe, directory, permissions, memory)
    @exit_code = 0
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

def DatalackeyProcess.options_for_OptionParser(parser, separator,
    exe_callable, mem_callable, dir_callable, perm_callable, echo_callable)
  unless separator.nil?
    unless separator.is_a? String
      separator = 'Options for case where this process runs datalackey:'
    end
    parser.separator separator
  end
  unless exe_callable.nil?
    parser.on("-l", "--lackey PROGRAM", "Use specified datalackey executable.") do |e|
      exe_callable.call(e)
    end
  end
  unless mem_callable.nil?
    parser.on("-m", "--memory", "Store data in memory.") do
      mem_callable.call(true)
    end
  end
  unless dir_callable.nil?
    parser.on("-d", "--directory [DIR]", "Store data under (working) directory.") do |d|
      dir_callable.call(d || '')
    end
  end
  unless perm_callable.nil?
    parser.on("-p", "--permissions MODE", [:user, :group, :other], "File permissions cover (user, group, other).") do |p|
      perm_callable.call({ :user => "600", :group => "660", :other => "666" }[p])
    end
  end
  unless echo_callable.nil?
    parser.on('--echo', 'Echo communication with datalackey.') do
      echo_callable.call(true)
    end
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


class PatternAction
  @@internal_map = {
    :error => {
      :syntax => [
        [ '@', 'error', 'missing', '*' ],
        [ '@', 'error', 'not-string', '*' ],
        [ '@', 'error', 'not-string-null', '*' ],
        [ '@', 'error', 'pairless', '*' ],
        [ '@', 'error', 'unexpected', '*' ],
        [ '@', 'error', 'unknown', '*' ],
        [ '@', 'error', 'command', 'missing', '?' ],
        [ '@', 'error', 'command', 'not-string', '?' ],
        [ '@', 'error', 'command', 'unknown', '?' ]
      ],
      :user_id => [ nil, 'error', 'identifier', '?' ],
      :format => [ nil, 'error', 'format' ]
    },
    :stored => [ nil, 'data', 'stored', '?', '?' ],
    :deleted => [ nil, 'data', 'deleted', '?', '?' ],
    :data_error => [ nil, 'data', 'error', '?', '?' ],
    :started => [ nil, 'process', 'started', '?', '?' ],
    :ended => [ nil, 'process', 'ended', '?', '?' ],
    :version => [ '@', 'version', "", '?' ],
    :done => [ '@', 'done', "" ],
    :child => [ '@', 'run', 'running', '?' ]
  }

  attr_reader :identifier, :internal
  attr_accessor :exit, :command, :status, :generators

  def initialize(action_maps_array, message_callables = [],
      identifier_placeholder = '@')
    @pattern2act = { }
    @fixed2act = { }
    @identifier = identifier_placeholder
    @exit = nil
    @command = nil
    @status = nil
    @generators = message_callables.is_a?(Array) ? message_callables.clone : [ message_callables ]
    firsts = { }
    action_maps_array.each { |m| fill_pattern2action_maps(firsts, [], m) }
    # Ensure we use unique key for internal mapping.
    @internal = ''
    chars = 'qwertyuiopasdfghjklzxcvbnm1234567890'
    rng = Random.new
    while firsts.has_key? @internal
      @internal = @internal + chars[rng.rand(chars.length)]
    end
    fill_pattern2action_maps({ }, [ @internal ], [ @@internal_map ])
    @pattern2act.each_value { |acts| acts.uniq! }
    @fixed2act.each_value { |acts| acts.uniq! }
  end

  def fill_pattern2action_maps(firsts, actionlist, item)
    if item.is_a? Array
      unless item.first.is_a?(Array) or item.first.is_a?(Hash)
        # item is a pattern.
        raise ArgumentError.new('Pattern-array must be under action.' + item.to_s) if actionlist.empty?
        wildcards = false
        pattern = []
        item.each do |element|
          case element
          when @identifier then pattern.push :identifier
          when '?'
            wildcards = true
            pattern.push :one
          when '*'
            wildcards = true
            pattern.push :rest
            break
          else pattern.push element
          end
        end
        tgt = wildcards ? @pattern2act : @fixed2act
        tgt[pattern] = [] unless tgt.has_key? pattern
        tgt[pattern].push actionlist
        firsts[actionlist.first] = true
        return
      end
      item.each { |sub| fill_pattern2action_maps(firsts, actionlist, sub) }
    elsif item.is_a? Hash
      item.each_pair do |action, sub|
        acts = actionlist.clone
        acts.push action
        fill_pattern2action_maps(firsts, acts, sub)
      end
    else
      raise ArgumentError.new('Item not a mapping, array, or pattern-array.')
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

  def replace_identifier(identifier, p2a)
    altered = { }
    p2a.each_pair do |pattern, a|
      p = []
      pattern.each { |item| p.push(item == :identifier ? identifier : item) }
      altered[p] = a
    end
    return altered
  end

  def set_identifier(identifier)
    @pattern2act = replace_identifier(identifier, @pattern2act)
    @fixed2act = replace_identifier(identifier, @fixed2act)
    @identifier = identifier
  end

  def best_match(message_array)
    return [ @fixed2act[message_array], [] ] if @fixed2act.has_key? message_array
    best_length = 0
    best = nil
    best_vars = nil
    @pattern2act.each_pair do |pattern, act|
      next if message_array.length + 1 < pattern.length
      next if pattern.last != :rest and message_array.length != pattern.length
      length = 0
      exact_length = 0
      found = true
      vars = []
      pattern.each_index do |idx|
        if pattern[idx] == :rest
          vars.concat message_array[idx...message_array.length]
          break
        end
        if pattern[idx] == :one
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
        best = act
        best_vars = vars
      elsif best_length < length
        best_length = length
        best = act
        best_vars = vars
      end
    end
    return best, best_vars
  end
end


class DatalackeyIO
  attr_reader :syntax, :version

  def initialize(to_datalackey, from_datalackey, notification_callable = nil,
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
    @children = { }
    @version = { }
    @read_datalackey = Thread.new do
      accum = []
      while true do
        begin
          raw = @from_datalackey.readpartial(32768)
        rescue IOError
          break
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
          act, vars = tracker.best_match(msg)
          next if act.nil?
          if msg[0].nil?
            actionable = []
            act.each do |item|
              next if item.first != tracker.internal # Some other uses the pattern.
              rest = item[1...item.length]
              name = vars.first
              id = vars.last
              # Messages from different threads may arrive out of order so
              # new data/process may be in book-keeping when previous should
              # be removed. With data these imply over-writing immediately,
              # with processes re-use of identifier and running back to back.
              case rest.first
              when :stored
                @dataprocess_mutex.synchronize do
                  if @data[name] < id
                    @data[name] = id
                    actionable.push rest
                  end
                end
              when :deleted
                @dataprocess_mutex.synchronize do
                  if @data.has_key?(name) and @data[name] <= id
                    @data.delete name
                    actionable.push rest
                  end
                end
              when :data_error
                @dataprocess_mutex.synchronize do
                  @data.delete(name) if @data[name] == id
                  actionable.push rest
                end
              when :started
                @dataprocess_mutex.synchronize { @process[name] = id }
                actionable.push rest
              when :child
                @dataprocess_mutex.synchronize { @children[name] = id }
              when :ended
                @dataprocess_mutex.synchronize do
                  if @process[name] == id
                    @process.delete(name)
                    @children.delete(name)
                  end
                  actionable.push rest
                end
              when :error
                if item[2] == :format
                  @to_datalackey_mutex.synchronize { @to_datalackey.putc 0 }
                end
                actionable.push rest
              end
            end
            next if notification_callable.nil?
            actionable.each do |rest|
              notification_callable.call(rest, msg, vars)
            end
            next # Notifications have been sent, no generators in nil tracker.
          end
          finish = false
          act.each do |item|
            if item.first != tracker.internal
              tracker.generators.each do |p|
                break if p.call(item, msg, vars)
              end
              next unless msg[0] == @waiting
              case item.first
              when :return, 'return' then finish = true
              when :error, 'error' then finish = true
              end
              next
            end
            next unless msg[0] == @waiting # Only command-specific messages.
            case item[1]
            when :done
              finish = true
              @tracked_mutex.synchronize { @tracked.delete(msg[0]) }
            when :version
              @syntax = msg[3]['commands']
              @version = { }
              msg.last.each_pair do |key, value|
                @version[key] = value if value.is_a? Integer
              end
            end
          end
          if finish
            tracker.exit = act
            @tracked_mutex.synchronize { @waiting = nil }
            @return_mutex.synchronize { @return_condition.signal }
          end
        end
        accum.push(raw) if raw.length > 0
      end
      @from_datalackey.close
      @return_mutex.synchronize { @return_condition.signal }
    end
    # Outside thread block.
    send(PatternAction.new([]), ['version'])
  end

  def data
    @dataprocess_mutex.synchronize { return @data.clone }
  end

  def process
    @dataprocess_mutex.synchronize { return @process.clone }
  end

  def launched
    @dataprocess_mutex.synchronize { return @children.clone }
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
    @tracked_mutex.synchronize do
      @tracked[id] = tracker unless id.nil?
      @waiting = id
    end
    dump(tracker.command)
    return tracker if id.nil? # There will be no responses.
    @return_mutex.synchronize { @return_condition.wait(@return_mutex) }
    tracker.status = true
    unless tracker.exit.nil?
      tracker.exit.each do |item|
        tracker.status = false if item.first == :error or item.first == 'error'
      end
    end
    return tracker
  end

  def dump(json_as_string)
    @to_datalackey_mutex.synchronize {
      begin
        @to_datalackey.write json_as_string
        @to_datalackey.flush
        @to_datalackey_echo.call(json_as_string) unless @to_datalackey_echo.nil?
      rescue Errno::EPIPE
      end
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
        rescue IOError
          break # It is possible that close happens in another thread.
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
        rescue IOError
          break # It is possible that close happens in another thread.
        rescue EOFError
          break
        end
      end
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
