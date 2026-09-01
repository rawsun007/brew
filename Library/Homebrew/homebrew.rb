# typed: strict
# frozen_string_literal: true

require "context"
require "utils/output"

module Homebrew
  extend Context

  sig { params(path: T.nilable(T.any(String, Pathname))).returns(T::Boolean) }
  def self.require?(path)
    return false if path.nil?

    if defined?(Warnings)
      # Work around require warning when done repeatedly:
      # https://bugs.ruby-lang.org/issues/21091
      Warnings.ignore(/already initialized constant/, /previous definition of/) do
        require path.to_s
      end
    else
      require path.to_s
    end
    true
  rescue LoadError
    false
  end

  # Need to keep this naming as-is for backwards compatibility.
  # rubocop:disable Naming/PredicateMethod
  sig {
    params(
      cmd:     T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.any(Pathname, String),
      options: T.untyped,
      _block:  T.nilable(T.proc.void),
    ).returns(T::Boolean)
  }
  def self._system(cmd, argv0 = nil, *args, **options, &_block)
    pid = fork do
      yield if block_given?
      args.map!(&:to_s)
      begin
        if argv0
          exec(cmd, argv0, *args, **options)
        else
          exec(cmd, *args, **options)
        end
      rescue
        nil
      end
      exit! 1 # never gets here unless exec failed
    end
    Process.wait(pid)
    $CHILD_STATUS.success? || false
  end
  private_class_method :_system
  # rubocop:enable Naming/PredicateMethod

  sig {
    params(
      cmd:     T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)]),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.any(Pathname, String),
      options: T.untyped,
    ).returns(T::Boolean)
  }
  def self.system(cmd, argv0 = nil, *args, **options)
    if verbose?
      out = (options[:out] == :err) ? $stderr : $stdout
      out.puts "#{cmd} #{args * " "}".gsub(RUBY_PATH.to_s, "ruby")
                                     .gsub($LOAD_PATH.join(File::PATH_SEPARATOR).to_s, "$LOAD_PATH")
    end
    _system(cmd, argv0, *args, **options)
  end

  sig {
    params(
      cmd:     T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.nilable(T.any(Pathname, String)),
      options: T.untyped,
    ).void
  }
  def self.safe_system(cmd, argv0 = nil, *args, **options)
    return if system(cmd, argv0, *args, **options)

    raise ErrorDuringExecution.new([cmd, argv0, *args], status: $CHILD_STATUS)
  end

  sig { params(args: T.any(Pathname, String), options: T.untyped).void }
  def self.safe_system_brew(*args, **options)
    safe_system HOMEBREW_BREW_FILE, *args, **options
  end

  sig {
    type_parameters(:Elem).params(
      values:              T::Array[T.type_parameter(:Elem)],
      words_connector:     String,
      two_words_connector: String,
      last_word_connector: String,
    ).returns(String)
  }
  def self.to_sentence(values, words_connector: ", ", two_words_connector: " and ", last_word_connector: " and ")
    case values.length
    when 0
      +""
    when 1
      +T.unsafe(values[0]).to_s
    when 2
      "#{values[0]}#{two_words_connector}#{values[1]}"
    else
      "#{T.must(values[0...-1]).join(words_connector)}#{last_word_connector}#{values[-1]}"
    end
  end

  sig {
    type_parameters(:Key, :Value).params(
      hash:       T::Hash[T.type_parameter(:Key), T.type_parameter(:Value)],
      valid_keys: T.any(T.type_parameter(:Key), T::Array[T.type_parameter(:Key)]),
    ).void
  }
  def self.assert_valid_keys(hash, *valid_keys)
    valid_keys.flatten!
    hash.each_key do |key|
      next if valid_keys.include?(key)

      raise ArgumentError,
            "Unknown key: #{T.unsafe(key).inspect}. " \
            "Valid keys are: #{valid_keys.map { |valid_key| T.unsafe(valid_key).inspect }.join(", ")}"
    end
  end

  sig {
    params(
      cmd:   T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0: T.nilable(T.any(String, [String, String])),
      args:  T.any(Pathname, String),
    ).returns(T::Boolean)
  }
  def self.quiet_system(cmd, argv0 = nil, *args)
    _system(cmd, argv0, *args) do
      # Redirect output streams to `/dev/null` instead of closing as some programs
      # will fail to execute if they can't write to an open stream.
      $stdout.reopen(File::NULL)
      $stderr.reopen(File::NULL)
    end
  end

  sig { params(env: T.nilable(String)).returns(T::Boolean) }
  def self.superenv?(env)
    return false if env == "std"

    !Superenv.bin.nil?
  end

  sig { params(formula: T.nilable(Formula)).void }
  def self.interactive_shell(formula = nil)
    unless formula.nil?
      ENV["HOMEBREW_DEBUG_PREFIX"] = formula.prefix.to_s
      ENV["HOMEBREW_DEBUG_INSTALL"] = formula.full_name
    end

    if Utils::Shell.preferred == :zsh && (home = Dir.home).start_with?(Utils::Path.resolved_path(HOMEBREW_TEMP).to_s)
      FileUtils.mkdir_p home
      FileUtils.touch "#{home}/.zshrc"
    end

    term = ENV.fetch("HOMEBREW_TERM", ENV.fetch("TERM", nil))
    with_env(TERM: term) do
      Process.wait fork { exec Utils::Shell.preferred_path(default: "/bin/bash") }
    end

    return if $CHILD_STATUS.success?
    raise "Aborted due to non-zero exit status (#{$CHILD_STATUS.exitstatus})" if $CHILD_STATUS.exited?

    raise $CHILD_STATUS.inspect
  end

  sig { type_parameters(:U).params(block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
  def self.with_homebrew_path(&block)
    with_env(PATH: PATH.new(ORIGINAL_PATHS).to_s, &block)
  end

  sig { params(silent: T::Boolean).returns(String) }
  def self.which_editor(silent: false)
    editor = Homebrew::EnvConfig.editor
    return editor if editor

    editor = %w[code codium cursor code-insiders subl mate bbedit vim].find do |candidate|
      candidate if which(candidate, ORIGINAL_PATHS)
    end
    editor ||= "vim"

    unless silent
      Utils::Output.opoo <<~EOS
        Using #{editor} because no editor was set in the environment.
        This may change in the future, so we recommend setting `$EDITOR`
        or `$HOMEBREW_EDITOR` to your preferred text editor.
      EOS
    end

    editor
  end

  sig { params(filenames: T.any(String, Pathname)).void }
  def self.exec_editor(*filenames)
    puts "Editing #{filenames.join "\n"}"
    with_homebrew_path { safe_system(*which_editor.shellsplit, *filenames) }
  end

  sig { params(args: T.any(String, Pathname)).void }
  def self.exec_browser(*args)
    browser = Homebrew::EnvConfig.browser
    browser ||= OS::PATH_OPEN if defined?(OS::PATH_OPEN)
    return unless browser

    ENV["DISPLAY"] = Homebrew::EnvConfig.display

    with_env(DBUS_SESSION_BUS_ADDRESS: ENV.fetch("HOMEBREW_DBUS_SESSION_BUS_ADDRESS", nil)) do
      safe_system(browser, *args)
    end
  end

  IGNORE_INTERRUPTS_MUTEX = Thread::Mutex.new.freeze

  sig { type_parameters(:U).params(_block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
  def self.ignore_interrupts(&_block)
    IGNORE_INTERRUPTS_MUTEX.synchronize do
      interrupted = T.let(false, T::Boolean)
      old_sigint_handler = trap(:INT) do
        interrupted = true

        $stderr.print "\n"
        $stderr.puts "One sec, cleaning up..."
      end

      begin
        yield
      ensure
        trap(:INT, old_sigint_handler)

        raise Interrupt if interrupted
      end
    end
  end

  sig {
    type_parameters(:U)
      .params(file: T.any(IO, Pathname, String), _block: T.proc.returns(T.type_parameter(:U)))
      .returns(T.type_parameter(:U))
  }
  def self.redirect_stdout(file, &_block)
    out = $stdout.dup
    $stdout.reopen(file)
    yield
  ensure
    $stdout.reopen(out)
    out.close
  end

  sig { params(name: String, formula_name: T.nilable(String), reason: String, latest: T::Boolean).returns(Pathname) }
  def self.ensure_executable!(name, formula_name = nil, reason: "", latest: false)
    formula_name ||= name

    executable = [
      which(name),
      which(name, ORIGINAL_PATHS),
      # Prefer the stable opt_bin path to a formula's executable during upgrades.
      HOMEBREW_PREFIX/"opt/#{formula_name}/bin/#{name}",
      HOMEBREW_PREFIX/"bin/#{name}",
    ].compact.find(&:exist?)
    return executable if executable

    require "formula"
    T.cast(Formula[formula_name].ensure_installed!(reason:, latest:, executable: name), Pathname)
  end

  # Uses $times global to share timing data between wrapped methods and the at_exit reporter.
  # rubocop:disable Style/GlobalVars
  sig { params(the_module: T::Module[T.anything], pattern: Regexp).void }
  def self.inject_dump_stats!(the_module, pattern)
    @injected_dump_stat_modules ||= T.let({}, T.nilable(T::Hash[T::Module[T.anything], T::Array[Symbol]]))
    @injected_dump_stat_modules[the_module] ||= []
    injected_methods = @injected_dump_stat_modules.fetch(the_module)
    wrapper = Module.new
    the_module.instance_methods.grep(pattern).each do |name|
      next if injected_methods.include? name

      injected_methods << name
      wrapper.define_method(name) do |*args, &block|
        require "time"

        time = Time.now

        begin
          super(*args, &block)
        ensure
          $times[name] ||= 0
          $times[name] += Time.now - time
        end
      end
    end
    the_module.prepend(wrapper)

    return unless $times.nil?

    $times = {}
    at_exit do
      col_width = [$times.keys.map(&:size).max.to_i + 2, 15].max
      $times.sort_by { |_k, v| v }.each do |method, time|
        puts format("%<method>-#{col_width}s %<time>0.4f sec", method: "#{method}:", time:)
      end
    end
  end
  # rubocop:enable Style/GlobalVars
end
