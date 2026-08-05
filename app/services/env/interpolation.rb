module Env
  # Resolves `$VAR` / `${VAR}` references inside .env values the way Docker
  # Compose does when it reads the file.
  #
  # This matters on import: a donor `.env` written by hand or by the old
  # configurator carries the *literal* text, but the containers only ever saw
  # the expanded result. A token like `abc$xyz` reaches InfluxDB as `abc`,
  # because `$xyz` is undefined and expands to nothing. Importing the literal
  # would persist a secret the stack never actually used — and HELIOS quotes it
  # on export, so the value suddenly changes for every recreated service (#377).
  #
  # References resolve against the variables defined earlier in the same file;
  # anything else expands to an empty string, mirroring Compose's "variable is
  # not set. Defaulting to a blank string". The environment of the HELIOS
  # process is deliberately not consulted — it is not the shell the user's
  # stack was started from.
  #
  # It lives under Env:: rather than Compose:: because the variable table is
  # always a .env file, and the backslash dialect `resolve_escaped` implements
  # exists only there — compose.yaml carries YAML quoting instead. The importer
  # reuses it for compose.yaml strings, which docker likewise resolves against
  # .env, so `${VAR}` has one meaning across HELIOS.
  module Interpolation
    NAME = /[A-Za-z_][A-Za-z0-9_]*/

    # The argument of `${VAR:-default}` is a value in its own right and may
    # nest further references, so it has to match balanced braces recursively —
    # `${DB_DATA:-${BASE}/postgres}` is one reference with a default, not a
    # reference to BASE wrapped in stray text.
    REFERENCE = /
      \$(?:
        \$                                                       # $$ — escaped literal $
        |
        \{(?<name>#{NAME})(?<operator>:?[-+?])?(?<argument>(?:[^{}]|\{\g<argument>\})*)\}
        |
        (?<bare>#{NAME})
      )
    /x

    # Inside double quotes Compose also processes backslash escapes, and it does
    # so in the same left-to-right pass: `\$` is a literal dollar that starts no
    # reference. Unescaping first and expanding afterwards would turn
    # `"\${HOME}"` into the value of HOME instead of the text `${HOME}`.
    ESCAPED_REFERENCE = /(?<escape>\\.)|#{REFERENCE}/m

    # Backslash sequences Compose expands inside double quotes; any other
    # escaped character stands for itself. Env::File inverts this table to
    # write those characters back out, so an entry added here keeps both
    # directions in step on its own.
    ESCAPE_SEQUENCES = { 'n' => "\n", 'r' => "\r", 't' => "\t" }.freeze

    module_function

    # For unquoted values, where a backslash is literal.
    def resolve(value, variables)
      return value unless value.include?('$')

      substitute(value, REFERENCE, variables)
    end

    # For the body of a double-quoted value, where escapes and references share
    # one pass.
    def resolve_escaped(value, variables)
      return value unless value.match?(/[$\\]/)

      substitute(value, ESCAPED_REFERENCE, variables)
    end

    # Names referenced by a string, for callers that need to know what a value
    # depends on rather than what it expands to. `$$` references nothing.
    # Names inside a default count too: `${DATA:-${BASE}/x}` depends on both,
    # and a caller that only saw BASE would drop DATA as unreferenced.
    def references(value)
      value.to_s.scan(REFERENCE).flat_map do |name, _operator, argument, bare|
        [name || bare, *references(argument)].compact
      end
    end

    def substitute(value, pattern, variables)
      value.gsub(pattern) do
        capture = Regexp.last_match.named_captures

        if (escape = capture['escape'])
          ESCAPE_SEQUENCES.fetch(escape[1], escape[1])
        elsif (bare = capture['bare'])
          variables[bare].to_s
        elsif (name = capture['name'])
          expand(variables[name], capture['operator']) do
            substitute(capture['argument'].to_s, pattern, variables)
          end
        else # `$$` — an escaped literal dollar
          '$'
        end
      end
    end

    # `${VAR-default}` substitutes when the variable is unset, `${VAR:-default}`
    # also when it is empty; `${VAR+alt}` / `${VAR:+alt}` do the opposite.
    # "Empty" is the empty string and nothing else — a value of whitespace is
    # set as far as Compose is concerned, so Rails' blankness must not stand in
    # for it, or both operators pick the wrong branch.
    # `${VAR:?message}` makes Compose abort — there is no stack to abort here,
    # so the reference falls back to the empty string like any unset variable.
    #
    # The argument arrives as a block because it is a value in its own right:
    # Compose interpolates the default it falls back to, so `${A:-$B}` yields
    # the contents of B, not the text `$B`. Only the branch that uses the
    # argument pays for that pass.
    def expand(value, operator)
      set = operator&.start_with?(':') ? !value.to_s.empty? : !value.nil?

      case operator&.delete_prefix(':')
      when '-' then set ? value : yield
      when '+' then set ? yield : ''
      else value.to_s
      end
    end
  end
end
