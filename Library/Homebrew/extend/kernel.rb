# typed: strict
# frozen_string_literal: true

require "utils/output"

# Homebrew extends Ruby's `Kernel` to make our code more readable.
# Extending Kernel makes these methods available globally.
# TODO: move all of these to other modules e.g. Utils.
module Kernel
  sig { params(env: T.nilable(String)).returns(T::Boolean) }
  def superenv?(env)
    Utils::Output.odeprecated "Kernel#superenv?", "Homebrew.superenv?"
    require "homebrew"

    Homebrew.superenv?(env)
  end
  private :superenv?

  sig { params(formula: T.nilable(Formula)).void }
  def interactive_shell(formula = nil)
    Utils::Output.odeprecated "Kernel#interactive_shell", "Homebrew.interactive_shell"
    require "homebrew"

    Homebrew.interactive_shell(formula)
  end

  sig { type_parameters(:U).params(block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
  def with_homebrew_path(&block)
    Utils::Output.odeprecated "Kernel#with_homebrew_path", "Homebrew.with_homebrew_path"
    require "homebrew"

    Homebrew.with_homebrew_path(&block)
  end

  # Kernel.system but with exceptions.
  sig {
    params(
      cmd:     T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.nilable(T.any(Pathname, String)),
      options: T.untyped,
    ).void
  }
  def safe_system(cmd, argv0 = nil, *args, **options)
    # odeprecated: remove this method in a later release, use `Homebrew.safe_system` directly instead
    require "homebrew"

    Homebrew.safe_system(cmd, argv0, *args, **options)
  end

  # Run a system command without any output.
  #
  # @api internal
  sig {
    params(
      cmd:   T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0: T.nilable(T.any(String, [String, String])),
      args:  T.any(Pathname, String),
    ).returns(T::Boolean)
  }
  def quiet_system(cmd, argv0 = nil, *args)
    # odeprecated: remove this method in a later release, use `Homebrew.quiet_system` directly instead
    require "homebrew"

    Homebrew.quiet_system(cmd, argv0, *args)
  end

  # Find a command.
  #
  # @api public
  # Keep in sync with `which` in Library/Homebrew/utils.sh.
  sig { params(cmd: String, path: PATH::Elements).returns(T.nilable(Pathname)) }
  def which(cmd, path = ENV.fetch("PATH"))
    PATH.new(path).each do |p|
      begin
        pcmd = File.expand_path(cmd, p)
      rescue ArgumentError
        # File.expand_path will raise an ArgumentError if the path is malformed.
        # See https://github.com/Homebrew/legacy-homebrew/issues/32789
        next
      end
      return Pathname.new(pcmd) if File.file?(pcmd) && File.executable?(pcmd)
    end
    nil
  end

  sig { params(silent: T::Boolean).returns(String) }
  def which_editor(silent: false)
    Utils::Output.odeprecated "Kernel#which_editor", "Homebrew.which_editor"
    require "homebrew"

    Homebrew.which_editor(silent:)
  end

  sig { params(filenames: T.any(String, Pathname)).void }
  def exec_editor(*filenames)
    Utils::Output.odeprecated "Kernel#exec_editor", "Homebrew.exec_editor"
    require "homebrew"

    Homebrew.exec_editor(*filenames)
  end

  sig { params(args: T.any(String, Pathname)).void }
  def exec_browser(*args)
    Utils::Output.odeprecated "Kernel#exec_browser", "Homebrew.exec_browser"
    require "homebrew"

    Homebrew.exec_browser(*args)
  end

  sig { type_parameters(:U).params(block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
  def ignore_interrupts(&block)
    Utils::Output.odeprecated "Kernel#ignore_interrupts", "Homebrew.ignore_interrupts"
    require "homebrew"

    Homebrew.ignore_interrupts(&block)
  end

  sig {
    type_parameters(:U)
      .params(file: T.any(IO, Pathname, String), block: T.proc.returns(T.type_parameter(:U)))
      .returns(T.type_parameter(:U))
  }
  def redirect_stdout(file, &block)
    Utils::Output.odeprecated "Kernel#redirect_stdout", "Homebrew.redirect_stdout"
    require "homebrew"

    Homebrew.redirect_stdout(file, &block)
  end

  # Ensure the given executable exists otherwise install the brewed version
  sig { params(name: String, formula_name: T.nilable(String), reason: String, latest: T::Boolean).returns(Pathname) }
  def ensure_executable!(name, formula_name = nil, reason: "", latest: false)
    Utils::Output.odeprecated "Kernel#ensure_executable!", "Homebrew.ensure_executable!"
    require "homebrew"

    Homebrew.ensure_executable!(name, formula_name, reason:, latest:)
  end

  # Calls the given block with the passed environment variables
  # added to `ENV`, then restores `ENV` afterwards.
  #
  # NOTE: This method is **not** thread-safe – other threads
  #       which happen to be scheduled during the block will also
  #       see these environment variables.
  #
  # ### Example
  #
  # ```ruby
  # with_env(PATH: "/bin") do
  #   system "echo $PATH"
  # end
  # ```
  #
  # @api public
  sig {
    type_parameters(:U)
      .params(
        hash:   T::Hash[Object, T.nilable(T.any(PATH, Pathname, String))],
        _block: T.proc.returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
  }
  def with_env(hash, &_block)
    old_values = {}
    begin
      hash.each do |key, value|
        key = key.to_s
        old_values[key] = ENV.delete(key)
        ENV[key] = value&.to_s
      end

      yield
    ensure
      ENV.update(old_values)
    end
  end
end
