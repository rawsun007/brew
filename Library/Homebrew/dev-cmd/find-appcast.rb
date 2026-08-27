# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "plist"
require "utils/curl"
require "yaml"

module Homebrew
  module DevCmd
    class FindAppcast < AbstractCommand
      cmd_args do
        description <<~EOS
          Find the appcast of the app bundle at <app_path>, e.g. for use in a
          cask `livecheck` block.

          Checks for a Sparkle `SUFeedURL` and Electron Builder update metadata.
        EOS

        named_args :app_path, number: 1
      end

      sig { override.void }
      def run
        app = Pathname(args.named.fetch(0))
        find_sparkle(app) || find_electron_builder(app)
      end

      private

      sig { params(appcast_type: String, urls: String).returns(T::Boolean) }
      def verify_appcast!(appcast_type, *urls)
        print "Looking for #{appcast_type} appcast: "
        urls.each do |url|
          next unless url_exist?(url)

          puts "Found appcast! \n"
          livecheck_strategy = if appcast_type == "Sparkle"
            ":sparkle"
          elsif appcast_type == "Electron Builder"
            ":electron_builder"
          end
          puts <<~EOS
            livecheck do
              url "#{url}"
              strategy #{livecheck_strategy}
            end
          EOS
          return true
        end
        puts "Not found."
        false
      end

      sig { params(url: String).returns(T::Boolean) }
      def url_exist?(url)
        Utils::Curl.curl_output("--location", "--fail", url).success?
      end

      sig { params(app: Pathname).returns(T::Boolean) }
      def find_sparkle(app)
        plist = app/"Contents/Info.plist"
        return false unless plist.file?

        url = Plist.parse_xml(plist, marshal: false)&.[]("SUFeedURL")&.strip
        return false if url.blank?

        verify_appcast!("Sparkle", url)
      end

      sig { params(app: Pathname).returns(T::Boolean) }
      def find_electron_builder(app)
        appcast_file = app/"Contents/Resources/app-update.yml"
        return false unless appcast_file.exist?

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
        return false if possible_appcasts.empty?

        verify_appcast!("Electron Builder", *possible_appcasts)
      end
    end
  end
end
