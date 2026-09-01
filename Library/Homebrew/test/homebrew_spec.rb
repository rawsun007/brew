# typed: true
# frozen_string_literal: true

require "homebrew"

# $times is the global used by inject_dump_stats! for recording method timings
# rubocop:disable Style/GlobalVars
RSpec.describe Homebrew do
  describe ".inject_dump_stats!" do
    before do
      $times = {}
    end

    after do
      $times = nil
    end

    it "wraps matching methods with timing" do
      klass = Class.new do
        def check_something
          "result"
        end
      end

      described_class.inject_dump_stats!(klass, /^check_/)

      expect(klass.new.check_something).to eq("result")
      expect($times).to have_key(:check_something)
    end

    it "does not recurse when a prepended module calls super" do
      klass = Class.new do
        def check_example
          "base"
        end
      end

      mod = Module.new do
        def check_example
          "#{super}_extended"
        end
      end

      klass.prepend(mod)
      described_class.inject_dump_stats!(klass, /^check_/)

      expect(klass.new.check_example).to eq("base_extended")
      expect($times).to have_key(:check_example)
    end

    it "only wraps methods matching the pattern" do
      klass = Class.new do
        def check_matched
          "matched"
        end

        def other_method
          "other"
        end
      end

      described_class.inject_dump_stats!(klass, /^check_/)

      instance = klass.new
      instance.check_matched
      instance.other_method

      expect($times).to have_key(:check_matched)
      expect($times).not_to have_key(:other_method)
    end
  end

  describe ".quiet_system" do
    it "returns true for a successful command" do
      expect(described_class.quiet_system("true")).to be true
    end

    it "returns false for a failing command" do
      expect(described_class.quiet_system("false")).to be false
    end
  end

  describe ".safe_system" do
    it "does not raise for a successful command" do
      expect { described_class.safe_system("true") }.not_to raise_error
    end

    it "raises for a failing command" do
      expect { described_class.safe_system("false") }.to raise_error(ErrorDuringExecution)
    end
  end

  describe ".safe_system_brew" do
    it "runs the current brew executable" do
      expect(described_class).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "install", "testball")

      described_class.safe_system_brew("install", "testball")
    end
  end

  describe ".to_sentence" do
    specify do
      expect(described_class.to_sentence([])).to eq("")
      expect(described_class.to_sentence(["one"])).to eq("one")
      expect(described_class.to_sentence(["one", "two"])).to eq("one and two")
      expect(described_class.to_sentence(["one", "two", "three"])).to eq("one, two and three")
      expect(described_class.to_sentence([1])).to eq("1")
      expect(described_class.to_sentence([nil, "one", "", "two", "three"])).to eq(", one, , two and three")
      expect(described_class.to_sentence([""])).not_to be_frozen
      expect(described_class.to_sentence(["one"])).not_to be_frozen
      expect(described_class.to_sentence(["one", "two"])).not_to be_frozen
      expect(described_class.to_sentence(["one", "two", "three"])).not_to be_frozen
    end

    it "converts values to a sentence with custom connectors" do
      expect(described_class.to_sentence(["one", "two", "three"], words_connector: " "))
        .to eq("one two and three")
      expect(described_class.to_sentence(["one", "two", "three"], words_connector: " & "))
        .to eq("one & two and three")
      expect(described_class.to_sentence(["one", "two", "three"], last_word_connector: ", and also "))
        .to eq("one, two, and also three")
      expect(described_class.to_sentence(["one", "two", "three"], last_word_connector: " "))
        .to eq("one, two three")
      expect(described_class.to_sentence(["one", "two"], two_words_connector: " ")).to eq("one two")
    end

    it "creates a new string" do
      elements = ["one"]
      expect(described_class.to_sentence(elements).object_id).not_to eq(elements[0].object_id)
    end
  end

  describe ".assert_valid_keys" do
    it "accepts valid keys" do
      expect { described_class.assert_valid_keys({ name: "Homebrew" }, :name) }.not_to raise_error
    end

    it "rejects invalid keys" do
      expect { described_class.assert_valid_keys({ name: "Homebrew" }, :version) }
        .to raise_error(ArgumentError, "Unknown key: :name. Valid keys are: :version")
    end
  end
end
# rubocop:enable Style/GlobalVars
