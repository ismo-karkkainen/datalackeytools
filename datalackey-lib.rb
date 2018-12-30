require 'yaml'
require 'json'


$generic_map = %q(
---
error:
- syntax: [ "@", "?", error, argument, invalid ]
- syntax: [ "@", "?", error, argument, not-integer ]
- syntax: [ "@", "?", missing, "*" ]
- syntax: [ "@", error, missing, "*" ]
- syntax: [ "@", error, not-string, "*" ]
- syntax: [ "@", error, not-string-null, "*" ]
- syntax: [ "@", error, pairless, "*" ]
- syntax: [ "@", error, unexpected, "*" ]
- syntax: [ "@", error, unknown, "*" ]
- syntax: [ "@", error, command, missing, "?" ]
- syntax: [ "@", error, command, not-string, "?" ]
- syntax: [ "@", error, command, unknown, "?" ]
- user_id: [ ~, error, identifier, "?" ]
- format: [ ~, error, format ]
return:
- done: [ "@", done, "" ]
process:
- started: [ ~, process, started, "?", "?" ]
- ended: [ ~, process, ended, "?", "?" ]
data:
- stored: [ ~, data, stored, "?", "?" ]
- deleted: [ ~, data, deleted, "?", "?" ]
- data_error: [ ~, data, error, "?", "?" ]
internal:
- stored: [ ~, data, stored, "?", "?" ]
- deleted: [ ~, data, deleted, "?", "?" ]
- data_error: [ ~, data, error, "?", "?" ]
- started: [ ~, process, started, "?", "?" ]
- ended: [ ~, process, ended, "?", "?" ]
- error_format: [ ~, error, format ]
- version: [ "@", version, "", "?" ]
- done: [ "@", done, "" ]
)


class DatalackeyProcess
  attr_reader :exit_code, :stdout, :stderr, :stdin

  def initialize(exe, directory, permissions, memory)
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


CategoryAction = Struct.new(:category, :action)

# Turn into obtaining at most three lists of mappings.

class PatternAction
  @@generic_map = YAML.load($generic_map)

  attr_reader :identifier
  attr_accessor :exit, :command, :status, :generators

  def initialize(action_maps_list, message_procs = [],
      generic_action_map = nil, identifier_placeholder = '@')
    raise ArgumentError.new('message_procs not an Array') unless
      message_procs.is_a? Array
    @pattern2ca = { }
    @fixed2ca = { }
    @identifier = identifier_placeholder
    @exit = nil
    @command = nil
    @status = nil
    @generators = message_procs
    maps = action_maps_list.clone
    maps.push(generic_action_map.nil? ? @@generic_map : generic_action_map)
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

  def initialize(to_datalackey, from_datalackey)
    @to_datalackey_mutex = Mutex.new
    @to_datalackey = to_datalackey
    @from_datalackey = from_datalackey
    @identifier = 0
    @tracked_mutex = Mutex.new
    @tracked = { nil => PatternAction.new([], [], nil, nil) }
    @tracked.default = nil
    @waiting = nil
    @return_mutex = Mutex.new
    @return_condition = ConditionVariable.new
    @message_mutex = Mutex.new
    @messages = []
    @dataprocess_mutex = Mutex.new
    @data = { }
    @data.default = 0
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
          accum.push(raw[0, loc]) if loc > 0 # Newline begins?
          raw = raw[loc + 1, raw.length - loc - 1]
          loc = raw.index("\n")
          joined = accum.join
          accum.clear
          next unless joined.length > 0
          msg = JSON.parse joined
          # See if we are interested in it.
          tracker = @tracked_mutex.synchronize { @tracked[msg[0]] }
          next if tracker.nil?
          ca, vars = tracker.best_match(msg)
          next if ca.nil?
          if msg[0].nil?
            ca.each do |item|
              next unless item.category == 'internal' or item.category == :internal
              case item.action
              when 'stored', :stored
                @dataprocess_mutex.synchronize {
                  @data[msg[3]] = msg.last unless msg.last < @data[msg[3]]
                }
              when 'deleted', :deleted
                @dataprocess_mutex.synchronize { @data.delete msg[3] }
              when 'data_error', :data_error
                @dataprocess_mutex.synchronize { @data.delete msg[3] }
              when 'started', :started
                @dataprocess_mutex.synchronize { @process[msg[3]] = msg.last }
              when 'ended', :ended
                @dataprocess_mutex.synchronize { @process.delete msg[3] }
              when 'error_format', :error_format
                @to_datalackey_mutex.synchronize { @to_datalackey.putc 0 }
              end
            end
          end
          # Generate needed messages.
          @message_mutex.synchronize {
            ca.each do |item|
              next if item.category == 'internal' or item.category == :internal
              msgs = []
              tracker.generators.each do |p|
                msgs = p.call(item.category, item.action, msg, vars)
                break unless msgs.empty?
              end
              @messages.concat(msgs)
            end
          }
          if msg[0] == @waiting and not @waiting.nil?
            finish = false
            ca.each do |item|
              case item.category
              when 'error', :error
                finish = true
              when 'return', :return
                finish = true
              when 'internal', :internal
                case item.action
                when 'done', :done
                  @tracked_mutex.synchronize { @tracked.delete(msg[0]) }
                when 'version', :version
                  @syntax = msg[3]['commands']
                  @version = { :datalackey => msg[3]['datalackey'],
                    :interface => msg[3]['interface'] }
                end
              end
            end
            if finish
              tracker.exit = ca
              @tracked_mutex.synchronize { @waiting = nil }
              @return_mutex.synchronize { @return_condition.signal }
            end
          end
        end
        accum.push(raw) if raw.length > 0
      end
      @from_datalackey.close
      @return_mutex.synchronize { @return_condition.signal }
    end
    send(PatternAction.new([]), ['version'])
  end

  def get_messages
    @message_mutex.synchronize {
      result = @messages
      @messages = []
      return result
    }
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

  def send(pattern_action, command, user_id = false, echo_target = nil)
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
      @tracked[id] = tracker
      @waiting = id
    }
    dump(tracker.command, echo_target)
    return tracker if id.nil? # There will be no responses.
    @return_mutex.synchronize { @return_condition.wait(@return_mutex) }
    tracker.status = true
    tracker.exit.each do |item|
      tracker.status = false if item.category == 'error'
    end
    return tracker
  end

  def dump(json_as_string, echo_target = nil)
    @to_datalackey_mutex.synchronize {
      @to_datalackey.write json_as_string
      @to_datalackey.flush
    }
    echo_target.puts(json_as_string) unless echo_target.nil?
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
    @input.close
    @reader.join
  end

  def readlines
    return []
  end
end
