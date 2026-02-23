# Helios

Web-based bootstrap helper and management interface for [SOLECTRUS](https://solectrus.de).

**Status:** Active development (Phase 2: Configuration) – see [docs/guides/phases.md](docs/guides/phases.md) for details.

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

1. Install [Caddy](https://caddyserver.com/) for local HTTPS:

```bash
brew install caddy
```

2. Add local domains to `/etc/hosts`:

```bash
echo "127.0.0.1 helios.localhost vite.helios.localhost" | sudo tee -a /etc/hosts
```

3. Setup the application to install gems and NPM packages and create the database:

```bash
bin/setup
```

4. Start the application locally:

```bash
bin/dev
```

This starts the app and opens https://helios.localhost in your default browser.

On the first run, Caddy will ask for your password to install its local CA certificate.

See [Development Guide](docs/guides/development.md) for details.

## License

MIT
