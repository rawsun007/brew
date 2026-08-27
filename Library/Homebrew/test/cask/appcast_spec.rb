# typed: true
# frozen_string_literal: true

require "cask/appcast"

RSpec.describe Cask::Appcast do
  let(:tmpdir) { Pathname(Dir.mktmpdir) }
  let(:app) { tmpdir/"Test.app" }

  after { FileUtils.rm_rf tmpdir }

  def write_info_plist(binary: false)
    (app/"Contents").mkpath
    info_plist = app/"Contents/Info.plist"
    info_plist.write <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>SUFeedURL</key>
        <string>https://example.com/appcast.xml</string>
      </dict>
      </plist>
    XML
    system "/usr/bin/plutil", "-convert", "binary1", info_plist.to_s, exception: true if binary
  end

  def write_app_update_yml(contents)
    (app/"Contents/Resources").mkpath
    (app/"Contents/Resources/app-update.yml").write contents
  end

  describe "::find" do
    it "returns nil when the app has no update metadata" do
      app.mkpath
      expect(described_class.find(app)).to be_nil
    end

    it "finds a Sparkle appcast in an XML Info.plist", :needs_macos do
      write_info_plist
      allow(described_class).to receive(:url_exist?).with("https://example.com/appcast.xml").and_return(true)
      expect(described_class.find(app)).to have_attributes(url: "https://example.com/appcast.xml", strategy: :sparkle)
    end

    it "finds a Sparkle appcast in a binary Info.plist", :needs_macos do
      write_info_plist binary: true
      allow(described_class).to receive(:url_exist?).with("https://example.com/appcast.xml").and_return(true)
      expect(described_class.find(app)).to have_attributes(url: "https://example.com/appcast.xml", strategy: :sparkle)
    end

    it "returns nil when the Sparkle feed URL does not resolve", :needs_macos do
      write_info_plist
      allow(described_class).to receive(:url_exist?).and_return(false)
      expect(described_class.find(app)).to be_nil
    end

    it "finds an Electron Builder appcast from a generic provider" do
      write_app_update_yml <<~YAML
        url: https://update.example.com
      YAML
      allow(described_class).to receive(:url_exist?).and_return(false)
      allow(described_class).to receive(:url_exist?)
        .with("https://update.example.com/latest-mac.yml").and_return(true)
      expect(described_class.find(app))
        .to have_attributes(url: "https://update.example.com/latest-mac.yml", strategy: :electron_builder)
    end

    it "finds an Electron Builder appcast from a GitHub provider release asset" do
      write_app_update_yml <<~YAML
        owner: example
        repo: exampleapp
      YAML
      github_url = "https://github.com/example/exampleapp/releases/latest/download/latest-mac.yml"
      allow(described_class).to receive(:url_exist?).and_return(false)
      allow(described_class).to receive(:url_exist?).with(github_url).and_return(true)
      expect(described_class.find(app)).to have_attributes(url: github_url, strategy: :electron_builder)
    end

    it "returns nil when no Electron Builder candidate URL resolves" do
      write_app_update_yml <<~YAML
        owner: example
        repo: exampleapp
      YAML
      allow(described_class).to receive(:url_exist?).and_return(false)
      expect(described_class.find(app)).to be_nil
    end
  end
end
