# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "descriptions"
require "search"
require "description_cache_store"
require "fileutils"

module Homebrew
  module Cmd
    class Opam < AbstractCommand
      cmd_args do
        description <<~EOS
          Display <formula>'s name and one-line description.
          The cache is created on the first search, making that search slower than subsequent ones.
        EOS
        flag   "--os=",
                description: "Download for the given operating system. " \
                     "(Pass `all` to download for all operating systems.)"
        flag   "--arch=",
                description: "Download for the given CPU architecture. " \
                     "(Pass `all` to download for all architectures.)"

        switch "-s", "--search",
               description: "Search both names and descriptions for <text>. If <text> is flanked by " \
                            "slashes, it is interpreted as a regular expression."
        switch "-n", "--name",
               description: "Search just names for <text>. If <text> is flanked by slashes, it is " \
                            "interpreted as a regular expression."
        switch "-d", "--description",
               description: "Search just descriptions for <text>. If <text> is flanked by slashes, " \
                            "it is interpreted as a regular expression."
        switch "--eval-all",
               description: "Evaluate all available formulae and casks, whether installed or not, to search their " \
                            "descriptions. Implied if `HOMEBREW_EVAL_ALL` is set."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."

        conflicts "--search", "--name", "--description"

        named_args [:formula, :cask, :text_or_regex], min: 1
      end

      def maybe_write(written, file, key, s)
        if ! written.has_key?(key)
          file.printf "%s\n", s
          written[key] = true
        end
      end

      def write(f)
        name = f.name.split("@").first
        dir = "packages/brew-#{name}/brew-#{name}.#{f.version}"
        if File.directory?(dir)
          puts "Formula #{name} already written"
          return
        end
        FileUtils.mkdir_p "packages/brew-#{name}/brew-#{name}.#{f.version}"
        File.open("packages/brew-#{name}/brew-#{name}.#{f.version}/opam", "w") do |file|
        file.printf "opam-version: \"2.0\"\n"
        file.printf "maintainer: \"unmaintened@nowhere.com\"\n"
        file.printf "authors: \"Homebrew\"\n"
        file.printf "synopsis: \"%s\"\n", f.desc
        file.printf "description: \"\"\"\n%s\"\"\"\n", f.desc
        os_arch_combinations = args.os_arch_combinations
        written = {}
        os_arch_combinations.each do |os, arch|
          bottle_tag = Utils::Bottles::Tag.new(system: os, arch:)
          bottle = f.bottle_for_tag(bottle_tag)
          if bottle.nil?
            next
          end
          hash = bottle.url.split(":")[2]
          manifest = bottle.github_packages_manifest_resource
          fname = File.basename(bottle.cached_download)
          str = "extra-source \"%s\" {\n  src:\n    \"%s\"\n  checksum: [\n    \"sha256=%s\"\n  ]\n}" % [fname, bottle.url, hash]
          maybe_write(written, file, fname, str)
          fname = File.basename(manifest.cached_download)
          str = "extra-source \"%s\" {\n  src:\n    \"%s\"\n}" % [fname, manifest.url]
          maybe_write(written, file, fname, str)
        end
        deps = f.recursive_dependencies.map(&:to_formula)
        file.printf "depends : [\n  \"brew-opam-vars\"\n"
        deps.each do |dep|
          dep_name = dep.name.split("@").first
          file.printf "  \"brew-%s\" {= \"%s\"}\n", dep_name, dep.version
          write(dep)
        end
        file.printf "]\n"
        file.printf "build-env: [\n  [HOMEBREW_NO_AUTO_UPDATE = \"1\"]\n  [HOMEBREW_NO_VERIFY_ATTESTATIONS = \"1\"]\n  [HOMEBREW_NO_INSTALL_FROM_API = \"1\"]\n]\n"
        file.printf "build: [\n"
        os_arch_combinations.each do |os, arch|
          bottle_tag = Utils::Bottles::Tag.new(system: os, arch:)
          bottle = f.bottle_for_tag(bottle_tag)
          if bottle.nil?
            next
          end
          hash = bottle.url.split(":")[2]
          manifest = bottle.github_packages_manifest_resource
          fname = File.basename(manifest.cached_download)
          str = "[ \"mv\" \"%s\" \"%%{brew-opam-vars:homebrew-cache-dir}%%/downloads\" ]\n" % fname
          maybe_write(written, file, "build"+fname, str)
          file.printf "[ \"mv\" \"%s\" \"%%{brew-opam-vars:homebrew-cache-dir}%%/downloads\" ] { brew-opam-vars:homebrew-macos-name = \"%s\" & brew-opam-vars:homebrew-macos-arch = \"%s\"}\n", File.basename(bottle.cached_download), os, arch
        end
        file.printf "[ \"brew\" \"install\" \"--force-bottle\" \"--ignore-dependencies\" \"-f\" \"%s\" ]\n", name
        file.printf "]\n"
        file.printf "remove: [\n  [ \"brew\" \"uninstall\" \"--force\" \"--ignore-dependencies\" \"%s\" ]\n]\n", name
        end
      end

      sig { override.void }
      def run
        search_type = if args.search?
          :either
        elsif args.name?
          :name
        elsif args.description?
          :desc
        end

        if search_type.present?
          if !args.eval_all? && !Homebrew::EnvConfig.eval_all? && Homebrew::EnvConfig.no_install_from_api?
            raise UsageError, "`brew opam --search` needs `--eval-all` passed or `HOMEBREW_EVAL_ALL` set!"
          end

          query = args.named.join(" ")
          string_or_regex = Search.query_regexp(query)
          return Search.search_descriptions(string_or_regex, args, search_type:)
        end

        desc = {}
        args.named.to_formulae_and_casks.each do |formula_or_cask|
          case formula_or_cask
          when Formula
            write(formula_or_cask)
          end
        end
      end
    end
  end
end
