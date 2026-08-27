# typed: true
# frozen_string_literal: true

require "cask/token_generator"

RSpec.describe Cask::TokenGenerator do
  describe "::generate" do
    it "generates a token from a simple app name" do
      expect(described_class.generate("Example App.app")).to eq "example"
    end

    it "removes version numbers and platform designations" do
      expect(described_class.generate("Software 1.2.3 for Mac.app")).to eq "software"
    end

    it "hyphenates multi-word names" do
      expect(described_class.generate("Fancy Word Processor")).to eq "fancy-word-processor"
    end

    it "spells out symbols" do
      expect(described_class.generate("Notes+")).to eq "notes-plus"
    end

    it "preserves terms following an interior version" do
      expect(described_class.generate("Software 2.0 Client")).to eq "software-client"
    end

    it "converts underscores to hyphens" do
      expect(described_class.generate("Fancy_Word")).to eq "fancy-word"
    end

    it "converts middots to hyphens" do
      expect(described_class.generate("Foo·Bar")).to eq "foo-bar"
    end
  end

  describe "::warnings" do
    it "warns about digits in tokens" do
      expect(described_class.warnings("app2")).not_to be_empty
    end
  end
end
