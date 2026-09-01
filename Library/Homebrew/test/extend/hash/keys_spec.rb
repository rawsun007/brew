# typed: true
# frozen_string_literal: true

require "extend/hash/keys"

RSpec.describe Hash do
  describe "#assert_valid_keys" do
    it "deprecates the Hash helper" do
      values = { name: "Homebrew" }
      expect(Utils::Output).to receive(:odeprecated).with("Hash#assert_valid_keys", "Homebrew.assert_valid_keys")
      expect(Homebrew).to receive(:assert_valid_keys).with(values, :name)

      values.assert_valid_keys(:name)
    end
  end
end
