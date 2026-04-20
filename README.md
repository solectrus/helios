# HELIOS

Web-based bootstrap helper and management interface for [SOLECTRUS](https://solectrus.de).

## What is HELIOS?

HELIOS eliminates the need to manually edit configuration files or understand Docker. Users install SOLECTRUS with a single command and manage it through a web interface.

## Documentation

| Document                                          | Description                                |
| ------------------------------------------------- | ------------------------------------------ |
| [Product overview](docs/product.md)               | Scenarios, features, technical constraints |
| [Architecture](docs/architecture/overview.md)     | System diagram, internal storage           |
| [Docker Integration](docs/architecture/docker.md) | Compose, volumes, health checks            |
| [ADRs](docs/adr/)                                 | Architecture Decision Records              |
| [Development Guide](docs/guides/development.md)   | Local setup, testing                       |
| [Open TODOs](docs/todos.md)                       | Work items still ahead                     |

## Adding HELIOS to an existing SOLECTRUS installation

### 1. Set the project name

HELIOS requires the Docker Compose project to be named `solectrus`. Add this line at the top of your `compose.yaml` (if it is not already there):

```yaml
name: solectrus
```

Without it, HELIOS will refuse to start and show a clear error message.

### 2. Add the HELIOS service

Append the following to your `compose.yaml`:

```yaml
helios:
  image: ghcr.io/solectrus/helios:develop
  environment:
    - ADMIN_PASSWORD
    - SECRET_KEY_BASE
  volumes:
    - .:/data
    - /var/run/docker.sock:/var/run/docker.sock
  ports:
    - 3999:3000
  restart: unless-stopped
```

No changes to `.env` are needed — `ADMIN_PASSWORD` and `SECRET_KEY_BASE` are reused from your existing SOLECTRUS setup.

### 3. Recreate the stack

Because adding `name: solectrus` changes the Compose project identity, recreate all containers so they are labeled correctly:

```bash
docker compose down
docker compose up -d
```

HELIOS is then available at `http://<your-host>:3999`.

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
