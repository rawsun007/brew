# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "system_command"
require "tap"

module Homebrew
  module DevCmd
    class GenerateCaskToken < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        description <<~EOS
          Generate a cask token, filename and header line for an application,
          following the token conventions described in the Cask Cookbook.

          The argument may be either a path to an application bundle
          (e.g. `/Applications/Example App.app`) or the vendor's name for the
          software (e.g. `Example App`).
        EOS

        named_args :app_or_name, number: 1
      end

      CASK_FILE_EXTENSION = ".rb"

      EXPANDED_SYMBOLS = T.let({
        "+" => "plus",
        "@" => "at",
      }.freeze, T::Hash[String, String])

      # Trailing patterns on app names that could be mistaken for version numbers etc.
      # but should be preserved.
      PRESERVE_TRAILING_PATS = T.let([
        /id3/i,
        /mp3/i,
        /3[\s-]*d/i,
        /diff3/i,
        /\A[^\d]+\+\Z/i,
      ].freeze, T::Array[Regexp])
      PRESERVE_TRAILING_PAT = /(?:#{Regexp.union(PRESERVE_TRAILING_PATS)})\Z/i

      # These patterns are applied repeatedly to the end of the app name until none
      # matches, after word breaks have been inserted at CamelCase and snake_case
      # transitions.
      REMOVE_TRAILING_PATS = T.let([
        # spaces
        /\s+/i,

        # generic terms
        /\bapp/i,
        /\b(?:quick[\s-]*)?launcher/i,

        # "mac", "for mac", "for OS X", "macOS", "for macOS".
        /\b(?:for)?[\s-]*mac(?:intosh|OS)?/i,
        /\b(?:for)?[\s-]*os[\s-]*x/i,

        # hardware designations such as "for x86", "32-bit", "ppc"
        /(?:\bfor\s*)?x.?86/i,
        /(?:\bfor\s*)?\bppc/i,
        /(?:\bfor\s*)?\d+.?bits?/i,

        # frameworks
        /\b(?:for)?[\s-]*(?:oracle|apple|sun)*[\s-]*(?:jvm|java|jre)/i,
        /\bgtk/i,
        /\bqt/i,
        /\bwx/i,
        /\bcocoa/i,

        # localizations
        /en\s*-\s*us/i,

        # version numbers
        /[^a-z0-9]+/i,
        /\b(?:version|alpha|beta|gamma|release|release.?candidate)(?:[\s.\d-]*\d[\s.\d-]*)?/i,
        /\b(?:v|ver|vsn|r|rc)[\s.\d-]*\d[\s.\d-]*/i,
        /\d+(?:[a-z.]\d+)*/i,
        /\b\d+\s*[a-z]/i,
        /\d+\s*[a-c]/i, # constrained to a-c b/c of false positives
      ].freeze, T::Array[Regexp])
      REMOVE_TRAILING_PAT = /(?<=.)(?:#{Regexp.union(REMOVE_TRAILING_PATS)})\Z/i

      # Patterns which are permitted (undisturbed) following an interior version number.
      AFTER_INTERIOR_VERSION_PAT = T.let(Regexp.union(
        /ce/i,
        /pro/i,
        /professional/i,
        /client/i,
        /server/i,
        /host/i,
        /viewer/i,
        /launcher/i,
        /installer/i,
      ).freeze, Regexp)

      sig { override.void }
      def run
        app_name = simplified_app_name(args.named.fetch(0))
        token = cask_token_for(app_name)
        file_name = "#{token}#{CASK_FILE_EXTENSION}"

        puts "Proposed Simplified App name: #{app_name}" if args.debug?
        puts "Proposed token:               #{token}"
        puts "Proposed file name:           #{file_name}"
        puts "Cask Header Line:             cask \"#{token}\" do"

        warnings = warnings_for(token)
        return if warnings.empty?

        warnings.each { |warning| opoo warning }
        Homebrew.failed = true
      end

      sig { params(app: String).returns(String) }
      def simplified_app_name(app)
        name = english_app_name(app.dup.force_encoding(Encoding::UTF_8))
        name = Pathname(name).basename.to_s if Pathname(name).exist?
        name = decompose_to_ascii(name).sub(/\.app\Z/i, "")
        remove_trailing_strings_and_versions(name)
      end

      sig { params(app_name: String).returns(String) }
      def cask_token_for(app_name)
        token = app_name.downcase
        EXPANDED_SYMBOLS.each do |symbol, word|
          token = token.gsub(symbol, " #{word} ")
        end
        token = token.sub(/ +\Z/, "")
                     .gsub(/ +/, "-")
                     .gsub(/[^a-z0-9-]+/, "")
                     .gsub(/--+/, "-")
                     .gsub(/\A-+|-+\z/, "")
                     .gsub(/-([0-9])/, '\1')
        raise UsageError, "Could not determine a token from '#{app_name}'." if token.empty?

        token
      end

      private

      # Attempt to find an English app name for an app bundle whose name on disk
      # contains non-ASCII characters.
      sig { params(app: String).returns(String) }
      def english_app_name(app)
        return app if app.ascii_only?

        app_path = Pathname(app)
        return app unless app_path.exist?

        candidates = [
          bundle_info_string(app_path, "CFBundleDisplayName"),
          bundle_info_string(app_path, "CFBundleName"),
          localized_app_name(app_path),
          bundle_info_string(app_path, "CFBundleExecutable"),
        ]
        candidates.compact.find(&:ascii_only?) || app
      end

      sig { params(app_path: Pathname, key: String).returns(T.nilable(String)) }
      def bundle_info_string(app_path, key)
        info_plist = app_path/"Contents/Info.plist"
        return unless info_plist.file?

        result = system_command "/usr/libexec/PlistBuddy",
                                args:         ["-c", "Print #{key}", info_plist],
                                print_stderr: false
        return unless result.success?

        result.stdout.lines.first&.force_encoding(Encoding::UTF_8)&.chomp
      end

      sig { params(app_path: Pathname).returns(T.nilable(String)) }
      def localized_app_name(app_path)
        strings_file = app_path/"Contents/Resources/en.lproj/InfoPlist.strings"
        strings_file = app_path/"Contents/Resources/English.lproj/InfoPlist.strings" unless strings_file.exist?
        return unless strings_file.exist?

        name_line = File.open(strings_file, "r:UTF-16LE:UTF-8") do |fh|
          fh.readlines.grep(/^CFBundle(?:Display)?Name\s*=\s*/).first
        end
        name_line&.[](/\ACFBundle(?:Display)?Name\s*=\s*"(.*)";\Z/, 1)
      end

      # Crudely (and incorrectly) decompose extended Latin characters to ASCII.
      sig { params(name: String).returns(String) }
      def decompose_to_ascii(name)
        name = name.tr("·‧・･", "-")
        return name if name.ascii_only?

        name.unicode_normalize(:nfkd).each_char.select(&:ascii_only?).join
      end

      sig { params(name: String).returns(String) }
      def remove_trailing_strings_and_versions(name)
        name = insert_word_breaks(name)
        loop do
          break if !name.match?(REMOVE_TRAILING_PAT) || name.match?(PRESERVE_TRAILING_PAT)

          name = name.sub(REMOVE_TRAILING_PAT, "")
        end
        remove_interior_versions(name).delete("\v")
      end

      # Hack a word break (vertical tab, later removed) between CamelCase and
      # snake_case transitions so that `REMOVE_TRAILING_PAT` can anchor on it.
      sig { params(name: String).returns(String) }
      def insert_word_breaks(name)
        trailing = name[PRESERVE_TRAILING_PAT]
        name = name.sub(PRESERVE_TRAILING_PAT, "") if trailing
        name = name.gsub(/([^A-Z])([A-Z])/, "\\1\v\\2").tr("_", " ")
        name = "#{name}#{trailing}" if trailing
        name
      end

      # Done separately from `REMOVE_TRAILING_PAT` because this requires a
      # substitution with a backreference.
      sig { params(name: String).returns(String) }
      def remove_interior_versions(name)
        name.sub(/(?<=.)[.\d]+(#{AFTER_INTERIOR_VERSION_PAT})\Z/io, '\1')
            .sub(/(?<=.)[\s.\d-]*\d[\s.\d-]*(#{AFTER_INTERIOR_VERSION_PAT})\Z/io, '-\1')
      end

      sig { params(token: String).returns(T::Array[String]) }
      def warnings_for(token)
        warnings = []
        if token.match?(/\d/)
          warnings << "'#{token}' contains digits. Digits which are version numbers should be removed."
        end

        tap = CoreCaskTap.instance
        if tap.installed? && (cask_path = tap.new_cask_path(token)).exist?
          warnings << "The file '#{cask_path}' already exists. " \
                      "Prepend the vendor name if this is not a duplicate."
        end
        warnings
      end
    end
  end
end
