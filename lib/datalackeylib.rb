# frozen_string_literal: true

# Copyright © 2019-2021 Ismo Kärkkäinen
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
      raise ArgumentError, 'datalackey not found' if exe.nil?
    elsif !File.exist?(exe) || !File.executable?(exe)
      raise ArgumentError, "Executable not found or not executable: #{exe}"
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
    parser.on('-l', '--lackey PROGRAM', 'Use specified datalackey executable.') do |e|
      exe_callable.call(e)
    end
  end
  unless mem_callable.nil?
    parser.on('-m', '--memory', 'Store data in memory.') do
      mem_callable.call(true)
    end
  end
  unless dir_callable.nil?
    parser.on('-d', '--directory [DIR]', 'Store data under (working) directory.') do |d|
      dir_callable.call(d || Dir.pwd)
    end
  end
  unless perm_callable.nil?
    parser.on('-p', '--permissions MODE', %i[user group other], 'File permissions cover (user, group, other).') do |p|
      perm_callable.call({ user: '600', group: '660', other: '666' }[p])
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
  return exe_name if File.exist?(exe_name) && File.executable?(exe_name)
  dirs = []
  dirs_outside_path = [ dirs_outside_path ] unless dirs_outside_path.is_a? Array
  dirs.concat dirs_outside_path
  dirs.concat ENV['PATH'].split(File::PATH_SEPARATOR)
  dirs.each do |d|
    exe = File.join(d, exe_name)
    return exe if File.exist?(exe) && File.executable?(exe)
  end
  nil
end

def DatalackeyProcess.verify_directory_permissions_memory(
    directory, permissions, memory)
  if !memory.nil? && !(directory.nil? && permissions.nil?)
    raise ArgumentError, 'Cannot use both memory and directory/permissions.'
  end
  if memory.nil?
    if directory.nil?
      directory = Dir.pwd
    elsif !Dir.exist? directory
      raise ArgumentError, "Given directory does not exist: #{directory}"
    end
    if permissions.nil?
      if (File.umask & 0o77).zero?
        permissions = '666'
      elsif (File.umask & 0o70).zero?
        permissions = '660'
      else
        permissions = '600'
      end
    elsif permissions != '600' && permissions != '660' && permissions != '666'
      raise ArgumentError, 'Permissions not in {600, 660, 666}.'
    end
  end
  [ directory, permissions, memory ]
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


# Intended to be used internaly when there are no patterns to act on.
# Instead of using this, pass nil to DatalakceyIO.send
class NoPatternNoAction
  attr_reader :identifier
  attr_accessor :exit, :command, :status, :message, :generators

  def initialize
    @exit = nil
    @command = nil
    @status = nil
    @message = nil
    @generators = []
  end

  def set_identifier(identifier)
    @identifier = identifier
  end

  def best_match(_)
    [ nil, [] ]
  end
end


class PatternAction < NoPatternNoAction
  def initialize(action_maps_array, message_callables = [])
    raise ArgumentError, 'action_maps_array is empty' unless action_maps_array.is_a?(Array) && !action_maps_array.empty?
    super()
    @pattern2act = { }
    @fixed2act = { }
    @generators = message_callables.is_a?(Array) ? message_callables.clone : [ message_callables ]
    action_maps_array.each do |m|
      raise ArgumentError, 'Action map is not a map.' unless m.is_a? Hash
      fill_pattern2action_maps([], m)
    end
    @pattern2act.each_value(&:uniq!)
    @fixed2act.each_value(&:uniq!)
    raise ArgumentError, 'No patterns.' if @pattern2act.empty? && @fixed2act.empty?
  end

  def fill_pattern2action_maps(actionlist, item)
    if item.is_a? Array
      unless item.first.is_a?(Array) || item.first.is_a?(Hash)
        # item is a pattern.
        raise ArgumentError, "Pattern-array must be under action: #{item}" if actionlist.empty?
        wildcards = false
        pattern = [ :identifier ]
        item.each do |element|
          case element
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
        tgt[pattern] = [] unless tgt.key? pattern
        tgt[pattern].push actionlist
        return
      end
      item.each { |sub| fill_pattern2action_maps(actionlist, sub) }
    elsif item.is_a? Hash
      item.each_pair do |action, sub|
        acts = actionlist.clone
        acts.push action
        fill_pattern2action_maps(acts, sub)
      end
    else
      raise ArgumentError, 'Item not a mapping, array, or pattern-array.'
    end
  end

  def clone
    gens = @generators
    @generators = nil
    copy = Marshal.load(Marshal.dump(self))
    @generators = gens
    copy.generators = gens.clone
    copy
  end

  def replace_identifier(identifier, p2a)
    altered = { }
    p2a.each_pair do |pattern, a|
      p = []
      pattern.each { |item| p.push(item == :identifier ? identifier : item) }
      altered[p] = a
    end
    altered
  end

  def set_identifier(identifier)
    @pattern2act = replace_identifier(identifier, @pattern2act)
    @fixed2act = replace_identifier(identifier, @fixed2act)
    @identifier = identifier
  end

  def best_match(message_array)
    return [ @fixed2act[message_array], [] ] if @fixed2act.key? message_array
    best_length = 0
    best = nil
    best_vars = []
    @pattern2act.each_pair do |pattern, act|
      next if message_array.length + 1 < pattern.length
      next if pattern.last != :rest && message_array.length != pattern.length
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
    [ best, best_vars ]
  end
end


class DatalackeyIO
  @@internal_notification_map = {
    error: {
      user_id: [ 'error', 'identifier', '?' ],
      format: [ 'error', 'format' ]
    },
    stored: [ 'data', 'stored', '?', '?' ],
    deleted: [ 'data', 'deleted', '?', '?' ],
    data_error: [ 'data', 'error', '?', '?' ],
    started: [ 'process', 'started', '?', '?' ],
    ended: [ 'process', 'ended', '?', '?' ]
  }

  @@internal_generic_map = {
    error: {
      syntax: [
        [ 'error', 'missing', '*' ],
        [ 'error', 'not-string', '*' ],
        [ 'error', 'not-string-null', '*' ],
        [ 'error', 'pairless', '*' ],
        [ 'error', 'unexpected', '*' ],
        [ 'error', 'unknown', '*' ],
        [ 'error', 'command', 'missing', '?' ],
        [ 'error', 'command', 'not-string', '?' ],
        [ 'error', 'command', 'unknown', '?' ]
      ]
    },
    done: [ 'done', '' ],
    child: [ 'run', 'running', '?' ]
  }

  def self.internal_notification_map
    Marshal.load(Marshal.dump(@@internal_notification_map))
  end

  def self.internal_generic_map
    Marshal.load(Marshal.dump(@@internal_generic_map))
  end

  attr_reader :syntax, :version

  def initialize(to_datalackey, from_datalackey, notification_callable = nil,
      to_datalackey_echo_callable = nil, from_datalackey_echo_callable = nil)
    @to_datalackey_mutex = Mutex.new
    @to_datalackey = to_datalackey
    @to_datalackey_echo = to_datalackey_echo_callable
    @from_datalackey = from_datalackey
    @identifier = 0
    @tracked_mutex = Mutex.new
    # Handling of notifications.
    @notify_tracker = PatternAction.new([ @@internal_notification_map ])
    @notify_tracker.set_identifier(nil)
    @internal = PatternAction.new([ @@internal_generic_map ])
    @tracked = Hash.new(nil)
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
      loop do
        begin
          raw = @from_datalackey.readpartial(32768)
        rescue IOError
          break
        rescue EOFError
          break
        end
        loc = raw.index("\n")
        until loc.nil?
          accum.push(raw[0, loc]) if loc.positive? # Newline at start ends line.
          raw = raw[loc + 1, raw.size - loc - 1]
          loc = raw.index("\n")
          joined = accum.join
          accum.clear
          next if joined.empty?
          from_datalackey_echo_callable.call(joined) unless from_datalackey_echo_callable.nil?
          msg = JSON.parse joined
          # See if we are interested in it.
          if msg.first.nil?
            act, vars = @notify_tracker.best_match(msg)
            next if act.nil?
            # We know there is only one action that matches.
            act = act.first
            actionable = nil
            name = vars.first
            id = vars.last
            # Messages from different threads may arrive out of order so
            # new data/process may be in book-keeping when previous should
            # be removed. With data these imply over-writing immediately,
            # with processes re-use of identifier and running back to back.
            case act.first
            when :stored
              @dataprocess_mutex.synchronize do
                if @data[name] < id
                  @data[name] = id
                  actionable = act
                end
              end
            when :deleted
              @dataprocess_mutex.synchronize do
                if @data.key?(name) && @data[name] <= id
                  @data.delete name
                  actionable = act
                end
              end
            when :data_error
              @dataprocess_mutex.synchronize do
                @data.delete(name) if @data[name] == id
              end
              actionable = act
            when :started
              @dataprocess_mutex.synchronize { @process[name] = id }
              actionable = act
            when :ended
              @dataprocess_mutex.synchronize do
                if @process[name] == id
                  @process.delete(name)
                  @children.delete(name)
                end
              end
              actionable = act
            when :error
              case act[1]
              when :format
                @to_datalackey_mutex.synchronize { @to_datalackey.putc 0 }
              when :user_id
                unless @waiting.nil?
                  # Does the waited command have invalid id?
                  begin
                    int = Integer(@waiting)
                    fract = @waiting - int
                    raise ArgumentError, '' unless fract.zero?
                  rescue ArgumentError, TypeError
                    unless @waiting.is_a? String
                      @tracked_mutex.synchronize do
                        trackers = @tracked[@waiting]
                        trackers.first.message = msg
                        trackers.first.exit = [ act ]
                        @tracked.delete(@waiting)
                        @waiting = nil
                      end
                      @return_mutex.synchronize { @return_condition.signal }
                    end
                  end
                end
              end
              actionable = act
            end
            next if notification_callable.nil? || actionable.nil?
            notification_callable.call(actionable, msg, vars)
            next
          end
          # Not a notification.
          trackers = @tracked_mutex.synchronize { @tracked[msg[0]] }
          next if trackers.nil?
          finish = false
          last = nil
          # Deal with user-provided PatternAction (or NoPatternNoAction).
          tracker = trackers.first
          act, vars = tracker.best_match(msg)
          unless act.nil?
            act.each do |item|
              tracker.generators.each do |p|
                break if p.call(item, msg, vars)
              end
              next unless msg.first == @waiting
              case item.first
              when :return, 'return'
                finish = true
                last = act if last.nil?
              when :error, 'error'
                finish = true
                last = act
              end
            end
          end
          # Check internal PatternAction.
          internal = trackers.last
          act, vars = internal.best_match(msg)
          unless act.nil?
            act = act.first # We know patterns are all unique in mapping.
            if act.first == :child
              @dataprocess_mutex.synchronize { @children[msg[0]] = vars.first }
            elsif msg.first == @waiting
              finish = true
              if act.first == :done
                @tracked_mutex.synchronize { @tracked.delete(msg[0]) }
              elsif act.first == :error
                last = [ act ]
              end
            end
          end
          if finish
            tracker.message = msg
            tracker.exit = last
            @tracked_mutex.synchronize { @waiting = nil }
            @return_mutex.synchronize { @return_condition.signal }
          end
        end
        accum.push(raw) unless raw.empty?
      end
      @from_datalackey.close
      @return_mutex.synchronize { @return_condition.signal }
    end
    # Outside thread block.
    send(PatternAction.new([{ version: [ 'version', '', '?' ] }], [
      proc do |action, message, vars|
        if action.first == :version
          @syntax = vars.first['commands']
          @version = { }
          vars.first.each_pair do |key, value|
            @version[key] = value if value.is_a? Integer
          end
          true
        else false
        end
      end
    ]), ['version'])
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
    @from_datalackey.closed?
  end

  def close
    @to_datalackey_mutex.synchronize { @to_datalackey.close }
  end

  def finish
    @read_datalackey.join
  end

  # Pass nil pattern_action if you are not interested in doing anything.
  def send(pattern_action, command, user_id = false)
    return nil if @to_datalackey_mutex.synchronize { @to_datalackey.closed? }
    if user_id
      id = command[0]
    else
      id = @identifier
      @identifier += 1
      command.prepend id
    end
    tracker = pattern_action.nil? ? NoPatternNoAction.new : pattern_action.clone
    tracker.set_identifier(id)
    tracker.command = JSON.generate(command)
    internal = @internal.clone
    internal.set_identifier(id)
    @tracked_mutex.synchronize do
      @tracked[id] = [ tracker, internal ] unless id.nil?
      @waiting = id
    end
    dump(tracker.command)
    return tracker if id.nil? # There will be no responses.
    @return_mutex.synchronize { @return_condition.wait(@return_mutex) }
    tracker.status = true
    unless tracker.exit.nil?
      tracker.exit.each do |item|
        tracker.status = false if item.first == :error || item.first == 'error'
      end
    end
    tracker
  end

  def dump(json_as_string)
    @to_datalackey_mutex.synchronize do
      @to_datalackey.write json_as_string
      @to_datalackey.flush
      @to_datalackey_echo.call(json_as_string) unless @to_datalackey_echo.nil?
    rescue Errno::EPIPE
      # Should do something in this case. Child process died?
    end
  end

  def verify(command)
    @syntax.nil? ? nil : true
  end
end


class StoringReader
  def initialize(input)
    @input = input
    @output_mutex = Mutex.new
    @output = [] # Contains list of lines from input.
    @reader = Thread.new do
      accum = []
      loop do
        begin
          raw = @input.readpartial(32768)
        rescue IOError
          break # It is possible that close happens in another thread.
        rescue EOFError
          break
        end
        loc = raw.index("\n")
        until loc.nil?
          accum.push(raw[0, loc]) if loc.positive? # Newline begins?
          unless accum.empty?
            @output_mutex.synchronize { @output.push(accum.join) }
            accum.clear
          end
          raw = raw[loc + 1, raw.size - loc - 1]
          loc = raw.index("\n")
        end
        accum.push(raw) unless raw.empty?
      end
    end
  end

  def close
    @input.close
    @reader.join
  end

  def getlines
    @output_mutex.synchronize do
      result = @output
      @output = []
      return result
    end
  end
end


class DiscardReader
  def initialize(input)
    @input = input
    return if input.nil?
    @reader = Thread.new do
      loop do
        @input.readpartial(32768)
      rescue IOError
        break # It is possible that close happens in another thread.
      rescue EOFError
        break
      end
    end
  end

  def close
    return if @input.nil?
    @input.close
    @reader.join
  end

  def getlines
    []
  end
end
