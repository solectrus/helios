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

## Adding Helios to an existing SOLECTRUS installation

### 1. Set the project name

Helios requires the Docker Compose project to be named `solectrus`. Add this line at the top of your `compose.yaml` (if it is not already there):

```yaml
name: solectrus
```

Without it, Helios will refuse to start and show a clear error message.

### 2. Add the Helios service

Append the following to your `compose.yaml`:

```yaml
helios:
  image: ghcr.io/solectrus/helios:develop
  user: root
  environment:
    - ADMIN_PASSWORD
    - SECRET_KEY_BASE
  volumes:
    - /opt/solectrus:/data
    - /var/run/docker.sock:/var/run/docker.sock
  ports:
    - 3999:3000
  restart: unless-stopped
```

Running as `root` is required to access the Docker socket and manage containers on the host.

No changes to `.env` are needed — `ADMIN_PASSWORD` and `SECRET_KEY_BASE` are reused from your existing SOLECTRUS setup.

### 3. Recreate the stack

Because adding `name: solectrus` changes the Compose project identity, recreate all containers so they are labeled correctly:

```bash
docker compose down
docker compose up -d
```

Helios is then available at `http://<your-host>:3999`.

## Development

1. Install dependencies from the [Brewfile](Brewfile):

```bash
brew bundle
```

2. Setup the application to install gems and NPM packages and create the database:

```bash
bin/setup
```

3. Start the application locally:

```bash
bin/dev
```

This starts the app and opens https://helios.localhost in your default browser.

On the first run, Caddy will ask for your password to install its local CA certificate.

See [Development Guide](docs/guides/development.md) for details.

## License

MIT
