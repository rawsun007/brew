# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "utils/bottles"
require "utils/portable_ruby"

module Homebrew
  module DevCmd
    class UpdatePortableRuby < AbstractCommand
      cmd_args do
        description <<~EOS
          Update the vendored `portable-ruby` from the current `portable-ruby` formula:
          write the version files and bottle checksums, run `brew vendor-install ruby`,
          then sync `utils/ruby.sh`, vendored gems and RBI files to the bundler shipped
          by the new ruby.
        EOS
        named_args :none

        hide_from_man_page!
      end

      sig { override.void }
      def run
        formula = Homebrew.with_no_api_env { Formulary.factory("portable-ruby") }
        version = formula.version.to_s
        pkg_version = formula.pkg_version.to_s
        vendor_dir = HOMEBREW_LIBRARY_PATH/"vendor"

        (vendor_dir/"portable-ruby-version").atomic_write("#{pkg_version}\n")
        (HOMEBREW_LIBRARY_PATH/".ruby-version").atomic_write("#{version}\n")

        formula.bottle_specification.checksums.each do |checksum|
          tag_symbol = checksum.fetch("tag")
          tag = Utils::Bottles::Tag.from_symbol(tag_symbol)
          os = tag.linux? ? "linux" : "darwin"
          path = vendor_dir/"portable-ruby-#{tag.standardized_arch}-#{os}"
          path.atomic_write("ruby_TAG=#{tag_symbol}\nruby_SHA=#{checksum.fetch("digest")}\n")
        end

        Homebrew.safe_system_brew "vendor-install", "ruby"

        bundler_version = Utils::PortableRuby.sync_bundler_version!(pkg_version)
        Homebrew.safe_system_brew "vendor-gems", "--no-commit",
                                  "--update=--ruby,--bundler=#{bundler_version}"
        Homebrew.safe_system_brew "typecheck", "--update"
      end
    end
  end
end
