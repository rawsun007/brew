# typed: strict
# frozen_string_literal: true

require "system_command"
require "utils/curl"
require "yaml"

module Cask
  # Discovers the appcast of an app bundle, for use in a cask `livecheck` block.
  #
  # Checks for a Sparkle `SUFeedURL` and Electron Builder update metadata.
  module Appcast
    extend SystemCommand::Mixin

    class Result < T::Struct
      const :url, String
      const :strategy, Symbol
    end

    sig { params(app: Pathname).returns(T.nilable(Result)) }
    def self.find(app)
      find_sparkle(app) || find_electron_builder(app)
    end

    sig { params(app: Pathname).returns(T.nilable(Result)) }
    def self.find_sparkle(app)
      info_plist = app/"Contents/Info.plist"
      return unless info_plist.file?

      # `PlistBuddy` rather than `Plist.parse_xml` to also handle binary plists.
      result = system_command "/usr/libexec/PlistBuddy",
                              args:         ["-c", "Print SUFeedURL", info_plist],
                              print_stderr: false
      return unless result.success?

      url = result.stdout.lines.first&.strip
      return if url.blank?
      return unless url_exist?(url)

      Result.new(url:, strategy: :sparkle)
    end
    private_class_method :find_sparkle

    sig { params(app: Pathname).returns(T.nilable(Result)) }
    def self.find_electron_builder(app)
      appcast_file = app/"Contents/Resources/app-update.yml"
      return unless appcast_file.exist?

      components = YAML.load_file(appcast_file, symbolize_names: true).compact

      possible_appcasts = [
        "#{components[:url]}/latest-mac.yml",
        "#{components[:url]}/updates/latest/mac/latest-mac.yml",
        "https://github.com/#{components[:owner]}/#{components[:repo]}/releases/latest/download/latest-mac.yml",
        "https://#{components[:bucket]}.s3.amazonaws.com/#{components[:channel]}/latest-mac.yml",
        "https://#{components[:bucket]}.s3.amazonaws.com/latest-mac.yml",
        "https://#{components[:bucket]}.s3.amazonaws.com/#{components[:path]}/latest-mac.yml",
        "https://s3-#{components[:region]}.amazonaws.com/#{components[:bucket]}/#{components[:path]}/latest-mac.yml",
        "https://s3.amazonaws.com/#{components[:bucket]}/#{components[:path]}/latest-mac.yml",
        "https://#{components[:name]}.#{components[:region]}.digitaloceanspaces.com/latest-mac.yml",
        "https://#{components[:name]}.#{components[:region]}.digitaloceanspaces.com/#{components[:path]}/latest-mac.yml",
        "#{components[:endpoint]}/#{components[:bucket]}/#{components[:path]}/latest-mac.yml",
      ].select do |url|
        url.exclude?("///") && url.exclude?("//.")
      end

      url = possible_appcasts.find { |candidate| url_exist?(candidate) }
      return if url.nil?

      Result.new(url:, strategy: :electron_builder)
    end
    private_class_method :find_electron_builder

    sig { params(url: String).returns(T::Boolean) }
    def self.url_exist?(url)
      ::Utils::Curl.curl_output("--location", "--fail", url).success?
    end
    private_class_method :url_exist?
  end
end
