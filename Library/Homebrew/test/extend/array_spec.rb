# typed: strict
# frozen_string_literal: true

require "extend/array"

RSpec.describe Array do
  describe "#to_sentence" do
    it "deprecates the Array helper" do
      values = ["one", "two"]
      expect(Utils::Output).to receive(:odeprecated).with("Array#to_sentence", "Homebrew.to_sentence")
      expect(Homebrew).to receive(:to_sentence)
        .with(values, words_connector: ", ", two_words_connector: " and ", last_word_connector: " and ")
        .and_return("one and two")

      expect(values.to_sentence).to eq("one and two")
    end
  end
end
