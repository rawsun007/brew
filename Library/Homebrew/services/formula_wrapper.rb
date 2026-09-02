# typed: strict
# frozen_string_literal: true

require "utils/output"

# Wrapper for a formula to handle service-related stuff like parsing and
# generating the service/plist files.
module Homebrew
  module Services
    class FormulaWrapper
      include Utils::Output::Mixin

      # Access the `Formula` instance.
      sig { returns(Formula) }
      attr_reader :formula

      # Create a new `Service` instance from either a path or label.
      sig { params(path_or_label: T.any(Pathname, String)).returns(T.nilable(FormulaWrapper)) }
      def self.from(path_or_label)
        label = path_or_label.to_s.sub(/\.(plist|service)\z/, "")
        match = label.match(path_or_label_regex)
        return unless match

        begin
          new(Formulary.factory(T.must(match[2])), service_name: T.must(match[1]))
        rescue
          nil
        end
      end

      # Initialize a new `Service` instance with supplied formula.
      sig { params(formula: Formula, service_name: T.nilable(String)).void }
      def initialize(formula, service_name: nil)
        @formula = formula
        @service_name_override = service_name
        @status_output_success_type = T.let(nil, T.nilable(StatusOutputSuccessType))

        return if System.launchctl? || System.systemctl?

        raise UsageError, System::MISSING_DAEMON_MANAGER_EXCEPTION_MESSAGE
      end

      # Delegate access to `formula.name`.
      sig { returns(String) }
      def name
        @name ||= T.let(formula.name, T.nilable(String))
      end

      # Delegate access to `formula.service?`.
      sig { returns(T::Boolean) }
      def service?
        @service ||= T.let(formula.service?, T.nilable(T::Boolean))
      end

      # Delegate access to `formula.service.timed?`.
      sig { returns(T::Boolean) }
      def timed?
        return @timed unless @timed.nil?

        @timed = T.let(service? && load_service.timed?, T.nilable(T::Boolean))
        @timed ||= false
      end

      # Delegate access to `formula.service.keep_alive?`.
      sig { returns(T::Boolean) }
      def keep_alive?
        return @keep_alive unless @keep_alive.nil?

        @keep_alive = T.let(service? && load_service.keep_alive?, T.nilable(T::Boolean))
        @keep_alive ||= false
      end

      sig { returns(T::Array[Pathname]) }
      def path_dirs
        return [] unless service?

        load_service.path_dirs
      end

      # service_name delegates with formula.plist_name or formula.service_name
      # for systemd (e.g., `homebrew.<formula>`).
      sig { returns(String) }
      def service_name
        @service_name ||= T.let(
          if System.launchctl?
            @service_name_override || formula.plist_name
          else # System.systemctl?
            @service_name_override || formula.service_name
          end, T.nilable(String)
        )
      end

      sig { returns(T::Array[String]) }
      def service_names
        @service_names ||= T.let(
          if @service_name_override
            [@service_name_override]
          elsif System.launchctl?
            formula.plist_names
          else # System.systemctl?
            [formula.service_name]
          end, T.nilable(T::Array[String])
        )
      end

      # service_file delegates with formula.launchd_service_path or formula.systemd_service_path for systemd.
      sig { returns(Pathname) }
      def service_file
        service_files.fetch(0)
      end

      sig { returns(T::Array[Pathname]) }
      def service_files
        @service_files ||= T.let(
          if System.launchctl?
            formula.launchd_service_paths
          else # System.systemctl?
            [formula.systemd_service_path]
          end, T.nilable(T::Array[Pathname])
        )
      end

      sig { returns(Pathname) }
      def source_service_file
        service_files.find(&:exist?) || service_file
      end

      sig { returns(Pathname) }
      def timer_file
        @timer_file ||= T.let(formula.systemd_timer_path, T.nilable(Pathname))
      end

      sig { returns(String) }
      def timer_name
        @timer_name ||= T.let(timer_file.basename.to_s, T.nilable(String))
      end

      sig { returns(Pathname) }
      def timer_dest
        dest_dir + timer_file.basename
      end

      # Whether the service should be launched at startup
      sig { returns(T::Boolean) }
      def service_startup?
        @service_startup ||= T.let(
          if service?
            load_service.requires_root?
          else
            false
          end, T.nilable(T::Boolean)
        )
      end

      # Path to destination service directory. If run as root, it's `boot_path`, else `user_path`.
      sig { returns(Pathname) }
      def dest_dir
        System.root? ? System.boot_path : System.user_path
      end

      # Path to destination service. If run as root, it's in `boot_path`, else `user_path`.
      sig { returns(Pathname) }
      def dest
        dests.fetch(0)
      end

      sig { returns(T::Array[Pathname]) }
      def dests
        if System.launchctl?
          service_names.map { |name| dest_dir/service_file_basename(name) }
        else
          [dest_dir/service_file.basename]
        end
      end

      sig { returns(Pathname) }
      def registered_dest
        if System.launchctl?
          active_dest = dest_dir/service_file_basename(active_service_name)
          return active_dest if active_dest.exist?
        end

        dests.find(&:exist?) || dest
      end

      # Returns `true` if any version of the formula is installed.
      sig { returns(T::Boolean) }
      def installed?
        formula.any_version_installed?
      end

      sig { void }
      def reset_cache!
        @status_output_success_type = nil
      end

      # Returns `true` if the service is loaded, else false.
      sig { params(cached: T::Boolean).returns(T::Boolean) }
      def loaded?(cached: false)
        if System.launchctl?
          reset_cache! unless cached
          status_success
        else # System.systemctl?
          System::Systemctl.quiet_run("status", timed? ? timer_name : service_file.basename)
        end
      end

      sig { returns(T::Array[String]) }
      def loaded_service_names
        return [service_name] if System.systemctl? && loaded?
        return [] unless System.launchctl?

        service_names.select { |name| System.launchctl_service_running?(name) }
      end

      sig { returns(String) }
      def active_service_name
        status_output_success_type.service_name
      end

      # Returns `true` if service is present (e.g. .plist is present in boot or user service path), else `false`
      # Accepts `type` with values `:root` for boot path or `:user` for user path.
      sig { params(type: T.nilable(Symbol)).returns(T::Boolean) }
      def service_file_present?(type: nil)
        case type
        when :root
          boot_path_service_file_present?
        when :user
          user_path_service_file_present?
        else
          boot_path_service_file_present? || user_path_service_file_present?
        end
      end

      sig { returns(T.nilable(String)) }
      def owner
        if System.launchctl? && registered_dest.exist?
          # read the username from the plist file
          require "plist"
          plist = begin
            Plist.parse_xml(registered_dest.read, marshal: false)
          rescue
            nil
          end
          plist_username = plist["UserName"] if plist

          return plist_username if plist_username.present?
        end
        return "root" if boot_path_service_file_present?
        return System.user if user_path_service_file_present?

        nil
      end

      sig { returns(T::Boolean) }
      def pid?
        (pid = self.pid).present? && pid.positive?
      end

      sig { returns(T::Boolean) }
      def error?
        return false if pid?

        (exit_code = self.exit_code).present? && !exit_code.zero?
      end

      sig { returns(T::Boolean) }
      def unknown_status?
        status_output.blank? && !pid?
      end

      # Get current PID of daemon process from status output.
      sig { returns(T.nilable(Integer)) }
      def pid
        Regexp.last_match(1).to_i if status_output =~ pid_regex(status_type)
      end

      # Get current exit code of daemon process from status output.
      sig { returns(T.nilable(Integer)) }
      def exit_code
        Regexp.last_match(1).to_i if status_output =~ exit_code_regex(status_type)
      end

      sig { returns(T.nilable(String)) }
      def loaded_file
        Regexp.last_match(1) if status_output =~ loaded_file_regex(status_type)
      end

      sig { returns(T::Hash[Symbol, T.anything]) }
      def to_hash
        hash = {
          name:,
          service_name: active_service_name,
          running:      pid?,
          loaded:       loaded?(cached: true),
          schedulable:  timed?,
          pid:,
          exit_code:,
          user:         owner,
          status:       status_symbol,
          file:         service_file_present? ? registered_dest : source_service_file,
          registered:   service_file_present?,
          loaded_file:,
        }

        return hash unless service?

        service = load_service

        return hash if service.command.blank?

        hash[:command] = service.manual_command
        hash[:working_dir] = service.working_dir
        hash[:root_dir] = service.root_dir
        hash[:log_path] = service.log_path
        hash[:error_log_path] = service.error_log_path
        hash[:interval] = service.interval
        hash[:cron] = service.cron.presence

        hash
      end

      # Generate the service file content (plist or systemd unit),
      # including any per-service user environment variable overrides,
      # or read the package-provided service file if the formula's
      # service block does not define a command.
      sig { returns(String) }
      def service_contents
        if !service? || !load_service.command?
          source_service_file.read
        elsif System.launchctl?
          load_service.to_plist
        else
          load_service.to_systemd_unit
        end
      end

      private

      # The purpose of this function is to lazy load the Homebrew::Service class
      # and avoid nameclashes with the current Service module.
      # It should be used instead of calling formula.service directly.
      sig { returns(Homebrew::Service) }
      def load_service
        require "formula"

        formula.service
      end

      sig { returns(StatusOutputSuccessType) }
      def status_output_success_type
        @status_output_success_type ||= if System.launchctl?
          result = T.let(nil, T.nilable(StatusOutputSuccessType))
          service_names.each do |name|
            output, success, type = System.launchctl_find_service(name)
            next unless success

            candidate = StatusOutputSuccessType.new(output, success, type, name)
            result ||= candidate
            if status_pid(candidate)&.positive?
              result = candidate
              break
            end
          end
          result || StatusOutputSuccessType.new("", false, :launchctl_list, service_name)
        else # System.systemctl?
          cmd = ["status", service_name]
          output = System::Systemctl.popen_read(*cmd).chomp
          success = T.cast($CHILD_STATUS.present? && $CHILD_STATUS.success? && output.present?, T::Boolean)
          odebug [System::Systemctl.executable, System::Systemctl.scope, *cmd].join(" "), output
          StatusOutputSuccessType.new(output, success, :systemctl, service_name)
        end
      end

      sig { params(result: StatusOutputSuccessType).returns(T.nilable(Integer)) }
      def status_pid(result)
        match = result.output.match(pid_regex(result.type))
        match[1].to_i if match
      end

      sig { returns(String) }
      def status_output
        status_output_success_type.output
      end

      sig { returns(T::Boolean) }
      def status_success
        status_output_success_type.success
      end

      sig { returns(Symbol) }
      def status_type
        status_output_success_type.type
      end

      sig { returns(Symbol) }
      def status_symbol
        if pid?
          :started
        elsif !loaded?(cached: true)
          :none
        elsif (exit_code = self.exit_code).present? && exit_code.zero?
          if timed?
            :scheduled
          else
            :stopped
          end
        elsif error?
          :error
        elsif unknown_status?
          :unknown
        else
          :other
        end
      end

      sig { params(status_type: Symbol).returns(Regexp) }
      def exit_code_regex(status_type)
        @exit_code_regex ||= T.let({
          launchctl_list:  /"LastExitStatus"\ =\ ([0-9]*);/,
          launchctl_print: /last exit code = ([0-9]+)/,
          systemctl:       /\(code=exited, status=([0-9]*)\)|\(dead\)/,
        }, T.nilable(T::Hash[Symbol, Regexp]))
        @exit_code_regex.fetch(status_type)
      end

      sig { params(status_type: Symbol).returns(Regexp) }
      def pid_regex(status_type)
        @pid_regex ||= T.let({
          launchctl_list:  /"PID"\ =\ ([0-9]*);/,
          launchctl_print: /pid = ([0-9]+)/,
          systemctl:       /Main PID: ([0-9]*) \((?!code=)/,
        }, T.nilable(T::Hash[Symbol, Regexp]))
        @pid_regex.fetch(status_type)
      end

      sig { params(status_type: Symbol).returns(Regexp) }
      def loaded_file_regex(status_type)
        @loaded_file_regex ||= T.let({
          launchctl_list:  //, # not available
          launchctl_print: /path = (.*)/,
          systemctl:       /Loaded: .*? \((.*);/,
        }, T.nilable(T::Hash[Symbol, Regexp]))
        @loaded_file_regex.fetch(status_type)
      end

      sig { returns(T::Boolean) }
      def boot_path_service_file_present?
        boot_path = System.boot_path
        return false if boot_path.blank?

        service_names.any? { |name| (boot_path/service_file_basename(name)).exist? }
      end

      sig { returns(T::Boolean) }
      def user_path_service_file_present?
        user_path = System.user_path
        return false if user_path.blank?

        service_names.any? { |name| (user_path/service_file_basename(name)).exist? }
      end

      sig { params(name: String).returns(String) }
      def service_file_basename(name)
        extension = System.launchctl? ? ".plist" : ".service"
        "#{name}#{extension}"
      end

      sig { returns(Regexp) }
      private_class_method def self.path_or_label_regex
        /(homebrew(?>\.mxcl)?\.([\w+-.@]+))\z/
      end

      class StatusOutputSuccessType
        sig { returns(String) }
        attr_reader :output

        sig { returns(T::Boolean) }
        attr_reader :success

        sig { returns(Symbol) }
        attr_reader :type

        sig { returns(String) }
        attr_reader :service_name

        sig { params(output: String, success: T::Boolean, type: Symbol, service_name: String).void }
        def initialize(output, success, type, service_name)
          @output = output
          @success = success
          @type = type
          @service_name = service_name
        end
      end
    end
  end
end
