# typed: true
# frozen_string_literal: true

require "keg"
require "stringio"

RSpec.describe Keg do
  let(:dst) { HOMEBREW_PREFIX/"bin"/"helloworld" }
  let(:nonexistent) { Pathname.new("/some/nonexistent/path") }
  let!(:keg) { setup_test_keg("foo", "1.0") }
  let(:kegs) { [] }

  include FileUtils

  def setup_test_keg(name, version, suffix: nil)
    path = HOMEBREW_CELLAR/name/version
    (path/"bin").mkpath

    %w[hiworld helloworld goodbye_cruel_world].each do |file|
      touch path/"bin"/"#{file}#{suffix}"
    end

    keg = Keg.new(path)
    kegs << keg
    keg
  end

  before do
    (HOMEBREW_PREFIX/"bin").mkpath
    (HOMEBREW_PREFIX/"lib").mkpath
  end

  after do
    kegs.each(&:unlink)
    rmtree HOMEBREW_PREFIX/"lib"
  end

  specify "::all" do
    expect(described_class.all).to eq([keg])
  end

  specify "#empty_installation?" do
    %w[.DS_Store INSTALL_RECEIPT.json LICENSE.txt].each do |file|
      touch keg/file
    end

    expect(keg).to exist
    expect(keg).to be_a_directory
    expect(keg).not_to be_an_empty_installation

    FileUtils.rm_r(keg/"bin")
    expect(keg).to be_an_empty_installation

    (keg/"bin").mkpath
    touch keg.join("bin", "todo")
    expect(keg).not_to be_an_empty_installation
  end

  specify "#oldname_opt_records" do
    expect(keg.oldname_opt_records).to be_empty
    oldname_opt_record = HOMEBREW_PREFIX/"opt/oldfoo"
    oldname_opt_record.make_relative_symlink(HOMEBREW_CELLAR/"foo/1.0")
    expect(keg.oldname_opt_records).to eq([oldname_opt_record])
  end

  specify "#remove_oldname_opt_records" do
    oldname_opt_record = HOMEBREW_PREFIX/"opt/oldfoo"
    oldname_opt_record.make_relative_symlink(HOMEBREW_CELLAR/"foo/2.0")
    keg.remove_oldname_opt_records
    expect(oldname_opt_record).to be_a_symlink
    oldname_opt_record.unlink
    oldname_opt_record.make_relative_symlink(HOMEBREW_CELLAR/"foo/1.0")
    keg.remove_oldname_opt_records
    expect(oldname_opt_record).not_to be_a_symlink
  end

  describe "#link" do
    it "links a Keg" do
      expect(keg.link).to eq(3)
      (HOMEBREW_PREFIX/"bin").children.each do |c|
        expect(c.readlink).to be_relative
      end
    end

    context "with dry run set to true" do
      let(:options) { { dry_run: true } }

      it "only prints what would be done" do
        expect do
          expect(keg.link(**options)).to eq(0)
        end.to output(<<~EOF).to_stdout
          #{HOMEBREW_PREFIX}/bin/goodbye_cruel_world
          #{HOMEBREW_PREFIX}/bin/helloworld
          #{HOMEBREW_PREFIX}/bin/hiworld
        EOF

        expect(keg).not_to be_linked
      end
    end

    it "fails when already linked" do
      keg.link

      expect { keg.link }.to raise_error(Keg::AlreadyLinkedError)
    end

    it "fails when files exist" do
      touch dst

      expect { keg.link }.to raise_error(Keg::ConflictError)
    end

    it "ignores broken symlinks at target" do
      src = keg/"bin"/"helloworld"
      dst.make_symlink(nonexistent)
      keg.link
      expect(dst.readlink).to eq(src.relative_path_from(dst.dirname))
    end

    context "with overwrite set to true" do
      let(:options) { { overwrite: true } }

      it "overwrite existing files" do
        touch dst
        expect(keg.link(**options)).to eq(3)
        expect(keg).to be_linked
      end

      it "overwrites broken symlinks" do
        dst.make_symlink "nowhere"
        expect(keg.link(**options)).to eq(3)
        expect(keg).to be_linked
      end

      it "still supports dryrun" do
        touch dst

        options[:dry_run] = true

        expect do
          expect(keg.link(**options)).to eq(0)
        end.to output(<<~EOF).to_stdout
          #{dst}
        EOF

        expect(keg).not_to be_linked
      end
    end

    it "also creates an opt link" do
      expect(keg).not_to be_optlinked
      keg.link
      expect(keg).to be_optlinked
    end

    specify "pkgconfig directory is created" do
      link = HOMEBREW_PREFIX/"lib"/"pkgconfig"
      (keg/"lib"/"pkgconfig").mkpath
      keg.link
      expect(link.lstat).to be_a_directory
    end

    specify "cmake directory is created" do
      link = HOMEBREW_PREFIX/"lib"/"cmake"
      (keg/"lib"/"cmake").mkpath
      keg.link
      expect(link.lstat).to be_a_directory
    end

    specify "lib/cps directory is created" do
      link = HOMEBREW_PREFIX/"lib"/"cps"
      (keg/"lib"/"cps").mkpath
      keg.link
      expect(link.lstat).to be_a_directory
    end

    specify "share/cps directory is created" do
      link = HOMEBREW_PREFIX/"share"/"cps"
      (keg/"share"/"cps").mkpath
      keg.link
      expect(link.lstat).to be_a_directory
    end

    specify "share/pwsh directory is created" do
      link = HOMEBREW_PREFIX/"share"/"pwsh"
      (keg/"share"/"pwsh"/"completions").mkpath
      FileUtils.touch keg/"share"/"pwsh"/"completions"/"_test.ps1"
      keg.link
      expect(link.lstat).to be_a_directory
    end

    specify "symlinks are linked directly" do
      link = HOMEBREW_PREFIX/"lib"/"pkgconfig"

      (keg/"lib"/"example").mkpath
      (keg/"lib"/"pkgconfig").make_symlink "example"
      keg.link

      expect(Utils::Path.resolved_path(link)).to be_a_symlink
      expect(link.lstat).to be_a_symlink
    end

    context "when keg symlinks to another keg" do
      let(:other_keg) { setup_test_keg("bar", "1.0", suffix: "-bar") }
      let(:filename) { "libtest.dylib" }
      let(:file) { other_keg/"lib"/filename }

      before do
        file.dirname.mkpath
        touch file
        other_keg.link
      end

      it "ignores symlinks that have same relative path" do
        (keg/"lib"/filename).make_relative_symlink other_keg.opt_record/"lib"/filename
        keg.link
        expect(Utils::Path.resolved_path(HOMEBREW_PREFIX/"lib"/filename)).to eq file
      end

      it "links symlinks that have different relative path" do
        filename2 = "libtest2.dylib"
        (keg/"lib"/filename2).make_relative_symlink other_keg.opt_record/"lib"/filename
        keg.link
        expect(Utils::Path.resolved_path(HOMEBREW_PREFIX/"lib"/filename2)).to eq keg/"lib"/filename2
      end

      it "fails linking symlinks that use Cellar path" do
        (keg/"lib"/filename).make_relative_symlink other_keg/"lib"/filename
        expect { keg.link }.to raise_error(Keg::ConflictError)
      end
    end
  end

  describe "#unlink" do
    it "unlinks a Keg" do
      keg.link
      expect(dst).to be_a_symlink
      expect(keg.unlink).to eq(3)
      expect(dst).not_to be_a_symlink
    end

    it "prunes empty top-level directories" do
      mkpath HOMEBREW_PREFIX/"lib/foo/bar"
      mkpath keg/"lib/foo/bar"
      touch keg/"lib/foo/bar/file1"

      keg.unlink

      expect(HOMEBREW_PREFIX/"lib/foo").not_to be_a_directory
    end

    it "ignores .DS_Store when pruning empty directories" do
      mkpath HOMEBREW_PREFIX/"lib/foo/bar"
      touch HOMEBREW_PREFIX/"lib/foo/.DS_Store"
      mkpath keg/"lib/foo/bar"
      touch keg/"lib/foo/bar/file1"

      keg.unlink

      expect(HOMEBREW_PREFIX/"lib/foo").not_to be_a_directory
      expect(HOMEBREW_PREFIX/"lib/foo/.DS_Store").not_to exist
    end

    it "doesn't remove opt link" do
      keg.link
      keg.unlink
      expect(keg).to be_optlinked
    end

    it "preverves broken symlinks pointing outside the Keg" do
      keg.link
      dst.delete
      dst.make_symlink(nonexistent)
      keg.unlink
      expect(dst).to be_a_symlink
    end

    it "preverves broken symlinks pointing into the Keg" do
      keg.link
      Utils::Path.resolved_path(dst).delete
      keg.unlink
      expect(dst).to be_a_symlink
    end

    it "preverves symlinks pointing outside the Keg" do
      keg.link
      dst.delete
      dst.make_symlink(Pathname.new("/bin/sh"))
      keg.unlink
      expect(dst).to be_a_symlink
    end

    it "preserves real files" do
      keg.link
      dst.delete
      touch dst
      keg.unlink
      expect(dst).to be_a_file
    end

    it "ignores nonexistent file" do
      keg.link
      dst.delete
      expect(keg.unlink).to eq(2)
    end

    it "doesn't remove links to symlinks" do
      a = HOMEBREW_CELLAR/"a"/"1.0"
      b = HOMEBREW_CELLAR/"b"/"1.0"

      (a/"lib"/"example").mkpath
      (a/"lib"/"example2").make_symlink "example"
      (b/"lib"/"example2").mkpath

      a = described_class.new(a)
      b = described_class.new(b)
      a.link

      lib = HOMEBREW_PREFIX/"lib"
      expect(lib.children.length).to eq(2)
      expect { b.link }.to raise_error(Keg::ConflictError)
      expect(lib.children.length).to eq(2)
    end

    it "removes broken symlinks that conflict with directories" do
      a = HOMEBREW_CELLAR/"a"/"1.0"
      (a/"lib"/"foo").mkpath

      keg = described_class.new(a)

      link = HOMEBREW_PREFIX/"lib"/"foo"
      link.parent.mkpath
      link.make_symlink(nonexistent)

      keg.link

      expect(link).to be_a_directory
    end
  end

  describe "#optlink" do
    it "removes a stale versioned alias link" do
      setup_test_keg("foo", "0.9")
      stale_alias = HOMEBREW_PREFIX/"opt/foo@0"
      stale_alias.make_relative_symlink(HOMEBREW_CELLAR/"foo/0.9")

      keg.optlink

      expect(stale_alias).not_to exist
    end

    it "preserves the opt link for a versioned Formula" do
      versioned_keg = setup_test_keg("foo@1", "1.0")
      versioned_keg.optlink

      keg.optlink

      expect(versioned_keg).to be_optlinked
    end

    it "creates an opt link" do
      oldname_opt_record = HOMEBREW_PREFIX/"opt/oldfoo"
      oldname_opt_record.make_relative_symlink(HOMEBREW_CELLAR/"foo/1.0")
      keg_record = HOMEBREW_CELLAR/"foo"/"2.0"
      (keg_record/"bin").mkpath
      keg = described_class.new(keg_record)
      keg.optlink
      expect(keg_record).to eq(Utils::Path.resolved_path(oldname_opt_record))
      keg.uninstall
      expect(oldname_opt_record).not_to be_a_symlink
    end

    it "doesn't fail if already opt-linked" do
      keg.opt_record.make_relative_symlink Pathname.new(keg)
      keg.optlink
      expect(keg).to be_optlinked
    end

    it "replaces an existing directory" do
      keg.opt_record.mkpath
      keg.optlink
      expect(keg).to be_optlinked
    end

    it "replaces an existing file" do
      keg.opt_record.parent.mkpath
      keg.opt_record.write("foo")
      keg.optlink
      expect(keg).to be_optlinked
    end
  end

  describe "#relativize_prefix_symlinks!" do
    let(:keg_path) { HOMEBREW_CELLAR/"foo/1.0" }

    it "rewrites absolute symlinks into the prefix and cellar as relative ones" do
      (HOMEBREW_PREFIX/"opt/bar/lib").mkpath
      touch keg_path/"bin/hiworld"
      ln_s keg_path/"bin/hiworld", keg_path/"bin/self"
      ln_s HOMEBREW_PREFIX/"opt/bar/lib", keg_path/"bin/other"
      ln_s "/usr/bin/true", keg_path/"bin/system"

      keg.relativize_prefix_symlinks!

      expect((keg_path/"bin/self").readlink).to eq Pathname("hiworld")
      expect((keg_path/"bin/other").readlink).to eq Pathname("../../../../opt/bar/lib")
      expect((keg_path/"bin/system").readlink).to eq Pathname("/usr/bin/true")
    end

    it "retargets symlinks from the prefix a bottle was built for" do
      ln_s "/build/prefix/Cellar/foo/1.0/bin/hiworld", keg_path/"bin/built"

      keg.relativize_prefix_symlinks!(prefix: "/build/prefix", cellar: "/build/prefix/Cellar")

      expect((keg_path/"bin/built").readlink).to eq Pathname("hiworld")
    end
  end

  describe "#delete_node_gyp_debris!" do
    it "deletes intermediate node-gyp objects but keeps addons and other objects" do
      keg_path = HOMEBREW_CELLAR/"foo/1.0"
      build_dir = keg_path/"libexec/lib/node_modules/foo/build/Release"
      (build_dir/"obj.target/foo").mkpath
      touch build_dir/"obj.target/foo/binding.o"
      touch build_dir/"addon.node"
      touch build_dir/"binding.d"
      touch build_dir/"leveldb.a"
      (keg_path/"libexec/lib/node_modules/foo/lib").mkpath
      touch keg_path/"libexec/lib/node_modules/foo/lib/shipped.a"
      (keg_path/"lib").mkpath
      touch keg_path/"lib/crt1.o"

      keg.delete_node_gyp_debris!

      expect(build_dir/"obj.target").not_to exist
      expect(build_dir/"binding.d").not_to exist
      expect(build_dir/"leveldb.a").not_to exist
      expect(build_dir/"addon.node").to exist
      expect(keg_path/"libexec/lib/node_modules/foo/lib/shipped.a").to exist
      expect(keg_path/"lib/crt1.o").to exist
    end
  end

  describe "#strip_node_gyp_addons!" do
    let(:addon) { HOMEBREW_CELLAR/"foo/1.0/libexec/lib/node_modules/foo/build/Release/addon.node" }

    before do
      addon.dirname.mkpath
      addon.write "unstripped"
      allow(keg).to receive(:which).with("strip").and_return(Pathname("/usr/bin/strip"))
    end

    it "replaces addons under node_modules when strip succeeds" do
      allow(Homebrew).to receive(:quiet_system) do |*command|
        File.write(command.fetch(3), "stripped")
        true
      end

      keg.strip_node_gyp_addons!

      expect(addon.read).to eq "stripped"
    end

    it "leaves addons untouched when strip fails" do
      allow(Homebrew).to receive(:quiet_system).and_return(false)

      keg.strip_node_gyp_addons!

      expect(addon.read).to eq "unstripped"
    end
  end

  describe "#homebrew_created_file?" do
    it "identifies Homebrew service files" do
      plist_file = instance_double(Pathname, extname: ".plist", basename: Pathname.new("homebrew.foo.plist"))
      service_file = instance_double(Pathname, extname: ".service", basename: Pathname.new("homebrew.foo.service"))
      timer_file = instance_double(Pathname, extname: ".timer", basename: Pathname.new("homebrew.foo.timer"))
      regular_file = instance_double(Pathname, extname: ".txt", basename: Pathname.new("readme.txt"))
      non_homebrew_plist = instance_double(Pathname, extname:  ".plist",
                                                     basename: Pathname.new("com.example.foo.plist"))

      allow(plist_file.basename).to receive(:to_s).and_return("homebrew.foo.plist")
      allow(service_file.basename).to receive(:to_s).and_return("homebrew.foo.service")
      allow(timer_file.basename).to receive(:to_s).and_return("homebrew.foo.timer")
      allow(regular_file.basename).to receive(:to_s).and_return("readme.txt")
      allow(non_homebrew_plist.basename).to receive(:to_s).and_return("com.example.foo.plist")

      expect(keg.homebrew_created_file?(plist_file)).to be true
      expect(keg.homebrew_created_file?(service_file)).to be true
      expect(keg.homebrew_created_file?(timer_file)).to be true
      expect(keg.homebrew_created_file?(regular_file)).to be false
      expect(keg.homebrew_created_file?(non_homebrew_plist)).to be false
    end
  end

  specify "#link and #unlink" do
    expect(keg).not_to be_linked
    keg.link
    expect(keg).to be_linked
    keg.unlink
    expect(keg).not_to be_linked
  end
end
