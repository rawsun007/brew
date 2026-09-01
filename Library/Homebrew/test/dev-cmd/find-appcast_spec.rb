# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/find-appcast"

RSpec.describe Homebrew::DevCmd::FindAppcast do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "find-appcast"
end
