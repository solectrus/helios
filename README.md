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

1. Install and set up [puma-dev](https://github.com/puma/puma-dev) to use HTTPS for development. Do this on macOS:

```bash
sudo puma-dev -setup
puma-dev -install
puma-dev link

# Use Vite via puma-dev proxy
# Adopted from https://github.com/puma/puma-dev#webpack-dev-server
echo 3036 > ~/.puma-dev/vite.helios
```

4. Setup the application to install gems and NPM packages and create the database:

```bash
bin/setup
```

5. Start the application locally:

```bash
bin/dev
```

This starts the app and opens https://helios.test in your default browser (see `Procfile.dev`).

See [Development Guide](docs/guides/development.md) for details.

## License

MIT
