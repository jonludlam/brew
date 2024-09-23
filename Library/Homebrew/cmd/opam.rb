# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "descriptions"
require "search"
require "description_cache_store"

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
            f = T.cast(formula_or_cask, Formula)
            printf "opam-version: \"2.0\"\n"
            printf "maintainer: \"unmaintened@nowhere.com\"\n"
            printf "authors: \"Homebrew\"\n"
            printf "synopsis: \"%s\"\n", f.desc
            printf "description: \"\"\"\n%s\"\"\"\n", f.desc
            os_arch_combinations = args.os_arch_combinations
            os_arch_combinations.each do |os, arch|
              bottle_tag = Utils::Bottles::Tag.new(system: os, arch:)
              bottle = f.bottle_for_tag(bottle_tag)
              if bottle.nil?
                next
              end
              hash = bottle.url.split(":")[2]
              printf "url {\n  src:\n    \"%s\"\n  checksum: [\n    \"sha256=%s\"\n  ]\n}\n", bottle.url, hash
            end
            deps = f.recursive_dependencies.map(&:to_formula)
            printf "depends : [\n"
            deps.each do |dep|
              printf "  \"brew-%s\" {= \"%s\"}\n", dep.full_name, dep.version
            end
            printf "]\n"
          end
        end
      end
    end
  end
end
