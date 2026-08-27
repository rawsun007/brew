# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-token"

RSpec.describe Homebrew::DevCmd::GenerateCaskToken do
  it_behaves_like "parseable arguments"

  describe "token generation" do
    def token_for(name)
      cmd = described_class.new([name])
      cmd.cask_token_for(cmd.simplified_app_name(name))
    end

    it "generates a token from a simple app name" do
      expect(token_for("Example App.app")).to eq "example"
    end

    it "removes version numbers and platform designations" do
      expect(token_for("Software 1.2.3 for Mac.app")).to eq "software"
    end

    it "hyphenates multi-word names" do
      expect(token_for("Fancy Word Processor")).to eq "fancy-word-processor"
    end

    it "spells out symbols" do
      expect(token_for("Notes+")).to eq "notes-plus"
    end

    it "preserves terms following an interior version" do
      expect(token_for("Software 2.0 Client")).to eq "software-client"
    end

    it "converts underscores to hyphens" do
      expect(token_for("Fancy_Word")).to eq "fancy-word"
    end

    it "converts middots to hyphens" do
      expect(token_for("Foo·Bar")).to eq "foo-bar"
    end
  end
end
