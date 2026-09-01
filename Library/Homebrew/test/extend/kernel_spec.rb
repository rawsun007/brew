# typed: true
# frozen_string_literal: true

RSpec.describe Kernel do
  let(:dir) { mktmpdir }

  describe "#interactive_shell" do
    let(:shell) { dir/"myshell" }

    it "starts an interactive shell session" do
      File.write shell, <<~SH
        #!/bin/sh
        echo called > "#{dir}/called"
      SH

      FileUtils.chmod 0755, shell

      ENV["SHELL"] = shell

      expect { Homebrew.interactive_shell }.not_to raise_error
      expect(dir/"called").to exist
    end

    it "deprecates the Kernel helper" do
      expect(Utils::Output).to receive(:odeprecated).with("Kernel#interactive_shell", "Homebrew.interactive_shell")
      expect(Homebrew).to receive(:interactive_shell).with(nil)

      interactive_shell
    end
  end

  describe "#which" do
    let(:cmd) { dir/"foo" }

    before { FileUtils.touch cmd }

    it "returns the first executable that is found" do
      cmd.chmod 0744
      expect(which(File.basename(cmd), File.dirname(cmd))).to eq(cmd)
    end

    it "skips non-executables" do
      expect(which(File.basename(cmd), File.dirname(cmd))).to be_nil
    end

    it "skips malformed path and doesn't fail" do
      # 'which' should not fail if a path is malformed
      # see https://github.com/Homebrew/legacy-homebrew/issues/32789 for an example
      cmd.chmod 0744

      # ~~ will fail because ~foo resolves to foo's home and there is no '~' user
      path = ["~~", File.dirname(cmd)].join(File::PATH_SEPARATOR)
      expect(which(File.basename(cmd), path)).to eq(cmd)
    end
  end

  specify "#which_editor" do
    ENV["HOMEBREW_EDITOR"] = "vemate -w"
    ENV["HOMEBREW_PATH"] = dir

    editor = "#{dir}/vemate"
    FileUtils.touch editor
    FileUtils.chmod 0755, editor

    expect(Homebrew.which_editor).to eq("vemate -w")
  end

  specify "the Kernel #which_editor helper is deprecated" do
    expect(Utils::Output).to receive(:odeprecated).with("Kernel#which_editor", "Homebrew.which_editor")
    expect(Homebrew).to receive(:which_editor).with(silent: false).and_return("vim")

    expect(which_editor).to eq("vim")
  end

  describe "#with_env" do
    it "sets environment variables within the block" do
      expect(ENV.fetch("PATH")).not_to eq("/bin")
      with_env(PATH: "/bin") do
        expect(ENV.fetch("PATH", nil)).to eq("/bin")
      end
    end

    it "restores ENV after the block" do
      with_env(PATH: "/bin") do
        expect(ENV.fetch("PATH", nil)).to eq("/bin")
      end
      path = ENV.fetch("PATH", nil)
      expect(path).not_to be_nil
      expect(path).not_to eq("/bin")
    end

    it "restores ENV if an exception is raised" do
      expect do
        with_env(PATH: "/bin") do
          raise StandardError, "boom"
        end
      end.to raise_error(StandardError)

      path = ENV.fetch("PATH", nil)
      expect(path).not_to be_nil
      expect(path).not_to eq("/bin")
    end
  end

  describe "#quiet_system" do
    it "delegates to Homebrew.quiet_system" do
      expect(Utils::Output).not_to receive(:odeprecated)
      expect(Homebrew).to receive(:quiet_system).with("true", nil).and_return(true)
      expect(quiet_system("true")).to be true
    end
  end

  describe "#safe_system" do
    it "delegates to Homebrew.safe_system" do
      expect(Utils::Output).not_to receive(:odeprecated)
      expect(Homebrew).to receive(:safe_system).with("true", nil)
      safe_system("true")
    end
  end
end
