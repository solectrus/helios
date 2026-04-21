# ADR-0008: File Handling Rules

## Context

HELIOS reads and writes two external files:

- `compose.yaml` – Docker Compose configuration
- `.env` – Environment variables

Both files may contain user modifications (comments, custom variables, formatting). We need clear rules for how HELIOS handles these files.

## Decision

### compose.yaml

| Aspect           | Decision      | Rationale                                                                                                    |
| ---------------- | ------------- | ------------------------------------------------------------------------------------------------------------ |
| Comments         | Not preserved | Standard YAML parsers (Psych) don't support comment preservation. Acceptable since HELIOS manages this file. |
| Anchors/Aliases  | Not preserved | Resolved during parsing. Complex anchor preservation not worth the effort.                                   |
| Formatting       | Normalized    | HELIOS writes consistent formatting.                                                                         |
| Unknown services | Preserved     | User-added services (e.g., `traefik`) are kept as-is.                                                        |

### .env

| Aspect            | Decision      | Rationale                                           |
| ----------------- | ------------- | --------------------------------------------------- |
| Line comments     | Preserved     | `# Full line comment` kept in place.                |
| Inline comments   | Preserved     | `VAR=value # comment` kept intact.                  |
| Empty lines       | Preserved     | Maintain logical grouping.                          |
| Unknown variables | Preserved     | User-added variables kept as-is.                    |
| Multiline values  | Not supported | All values must be single-line. Simplifies parsing. |

## Consequences

**Positive:**

- Simple, robust parsing with standard libraries
- User customizations (services, variables) preserved
- Predictable behavior

**Negative:**

- Comments in compose.yaml lost on first HELIOS write
- YAML anchors/aliases resolved (may increase file size slightly)
- Users needing multiline values must use alternative encoding

**Implementation:**

```ruby
# compose.yaml: Standard YAML parsing
compose = YAML.load_file('compose.yaml')
File.write('compose.yaml', compose.to_yaml)

# .env: Custom parser preserving comments
env = EnvFile.load('.env')
env['NEW_VAR'] = 'value'
env.save  # Comments and unknown variables preserved
```
