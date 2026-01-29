# Helios

Web-based bootstrap helper and management interface for [SOLECTRUS](https://solectrus.de).

**Status:** In planning – see [docs/](docs/) for specifications.

## What is Helios?

Helios eliminates the need to manually edit configuration files or understand Docker. Users install SOLECTRUS with a single command and manage it through a web interface.

## Documentation

| Document                                          | Description                        |
| ------------------------------------------------- | ---------------------------------- |
| [Requirements](docs/spec/requirements.md)         | Functional and non-functional spec |
| [Architecture](docs/architecture/overview.md)     | Tech stack, system diagram         |
| [Docker Integration](docs/architecture/docker.md) | Compose, volumes, health checks    |
| [ADRs](docs/adr/)                                 | Architecture Decision Records      |
| [Development Guide](docs/guides/development.md)   | Local setup, testing               |
| [Phases](docs/guides/phases.md)                   | Phase 0, MVP, roadmap              |

## Development

```bash
bin/setup
bin/rails server -p 3999
```

See [Development Guide](docs/guides/development.md) for details.

## License

MIT
