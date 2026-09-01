# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-token"

RSpec.describe Homebrew::DevCmd::GenerateCaskToken do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "generate-cask-token"
end
