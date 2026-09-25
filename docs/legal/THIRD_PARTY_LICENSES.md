# Third-Party Licenses

HELIOS is distributed under the terms in [LICENSE.md](../../LICENSE.md).
It bundles or depends on third-party components that remain subject to
their own licenses. This file is the summary; full per-package notice
texts for JS runtime dependencies live in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Most Ruby gems ship
their notice inside their gem directory in the Docker image
(`/usr/local/bundle/gems/<name>-<version>/{MIT-LICENSE,LICENSE,LICENSE.txt}`),
and these are not duplicated here. A gem that ships no such file names its
upstream source in the About screen of HELIOS.

Regenerate with `bin/rake licenses:generate`.

## Base Image

The official HELIOS Docker image runs on Alpine Linux 3.24.1 and
contains the Ruby interpreter and the Docker CLI. The table below lists the
packages in that image, read from its Alpine package database. Alpine ships
no license text inside the image. The license text and the source code of
each package are available from the Alpine package index at
<https://pkgs.alpinelinux.org/>. For the packages under a GPL or LGPL
license, the copyright holder also supplies the corresponding source code
on request at info@solectrus.de.

| Package                  | License                                   |
| ------------------------ | ----------------------------------------- |
| `alpine-baselayout`      | GPL-2.0-only                              |
| `alpine-baselayout-data` | GPL-2.0-only                              |
| `alpine-keys`            | MIT                                       |
| `alpine-release`         | MIT                                       |
| `apk-tools`              | GPL-2.0-only                              |
| `brotli-libs`            | MIT                                       |
| `busybox`                | GPL-2.0-only                              |
| `busybox-binsh`          | GPL-2.0-only                              |
| `ca-certificates`        | MPL-2.0 AND MIT                           |
| `ca-certificates-bundle` | MPL-2.0 AND MIT                           |
| `docker-cli`             | Apache-2.0                                |
| `docker-cli-compose`     | Apache-2.0                                |
| `gcompat`                | NCSA                                      |
| `gmp`                    | LGPL-3.0-or-later OR GPL-2.0-or-later     |
| `jemalloc`               | BSD-2-Clause                              |
| `libapk`                 | GPL-2.0-only                              |
| `libcrypto3`             | Apache-2.0                                |
| `libffi`                 | MIT                                       |
| `libgcc`                 | GPL-2.0-or-later AND LGPL-2.1-or-later    |
| `libncursesw`            | X11                                       |
| `libpq`                  | PostgreSQL                                |
| `libssl3`                | Apache-2.0                                |
| `libstdc++`              | GPL-2.0-or-later AND LGPL-2.1-or-later    |
| `libucontext`            | ISC                                       |
| `lz4-libs`               | BSD-2-Clause AND GPL-2.0-or-later         |
| `musl`                   | MIT                                       |
| `musl-obstack`           | GPL-2.0-or-later                          |
| `musl-utils`             | MIT AND BSD-2-Clause AND GPL-2.0-or-later |
| `ncurses-terminfo-base`  | X11                                       |
| `postgresql-common`      | MIT                                       |
| `postgresql18-client`    | PostgreSQL                                |
| `readline`               | GPL-3.0-or-later                          |
| `ruby`                   | Ruby, BSD-2-Clause                        |
| `scanelf`                | GPL-2.0-only                              |
| `ssl_client`             | GPL-2.0-only                              |
| `tzdata`                 | Public-Domain                             |
| `yaml`                   | MIT                                       |
| `zlib`                   | Zlib                                      |
| `zstd-libs`              | BSD-3-Clause OR GPL-2.0-or-later          |

## Ruby Gems

| Package                | License            |
| ---------------------- | ------------------ |
| `accept_language`      | MIT                |
| `action_text-trix`     | MIT                |
| `actioncable`          | MIT                |
| `actionmailbox`        | MIT                |
| `actionmailer`         | MIT                |
| `actionpack`           | MIT                |
| `actiontext`           | MIT                |
| `actionview`           | MIT                |
| `activejob`            | MIT                |
| `activemodel`          | MIT                |
| `activerecord`         | MIT                |
| `activestorage`        | MIT                |
| `activesupport`        | MIT                |
| `aws-eventstream`      | Apache-2.0         |
| `aws-partitions`       | Apache-2.0         |
| `aws-sdk-core`         | Apache-2.0         |
| `aws-sdk-kms`          | Apache-2.0         |
| `aws-sdk-s3`           | Apache-2.0         |
| `aws-sigv4`            | Apache-2.0         |
| `base64`               | Ruby, BSD-2-Clause |
| `bigdecimal`           | Ruby, BSD-2-Clause |
| `bootsnap`             | MIT                |
| `brotli`               | MIT                |
| `builder`              | MIT                |
| `bundler`              | MIT                |
| `commonmarker`         | MIT                |
| `concurrent-ruby`      | MIT                |
| `connection_pool`      | MIT                |
| `crass`                | MIT                |
| `date`                 | Ruby, BSD-2-Clause |
| `docker-api`           | MIT                |
| `drb`                  | Ruby, BSD-2-Clause |
| `erb`                  | Ruby, BSD-2-Clause |
| `erubi`                | MIT                |
| `excon`                | MIT                |
| `globalid`             | MIT                |
| `i18n`                 | MIT                |
| `io-console`           | Ruby, BSD-2-Clause |
| `irb`                  | Ruby, BSD-2-Clause |
| `jmespath`             | Apache-2.0         |
| `json`                 | Ruby               |
| `logger`               | Ruby, BSD-2-Clause |
| `loofah`               | MIT                |
| `mail`                 | MIT                |
| `marcel`               | MIT, Apache-2.0    |
| `mini_mime`            | MIT                |
| `minitest`             | MIT                |
| `msgpack`              | Apache-2.0         |
| `multi_json`           | MIT                |
| `net-imap`             | Ruby, BSD-2-Clause |
| `net-pop`              | Ruby, BSD-2-Clause |
| `net-protocol`         | Ruby, BSD-2-Clause |
| `net-smtp`             | Ruby, BSD-2-Clause |
| `nio4r`                | MIT, BSD-2-Clause  |
| `nokogiri`             | MIT                |
| `pp`                   | Ruby, BSD-2-Clause |
| `prettyprint`          | Ruby, BSD-2-Clause |
| `prism`                | MIT                |
| `puma`                 | BSD-3-Clause       |
| `racc`                 | Ruby, BSD-2-Clause |
| `rack`                 | MIT                |
| `rack-brotli`          | MIT                |
| `rack-session`         | MIT                |
| `rack-test`            | MIT                |
| `rackup`               | MIT                |
| `rails`                | MIT                |
| `rails-dom-testing`    | MIT                |
| `rails-html-sanitizer` | MIT                |
| `rails_vite`           | MIT                |
| `railties`             | MIT                |
| `rake`                 | MIT                |
| `rbs`                  | BSD-2-Clause, Ruby |
| `rdoc`                 | Ruby, GPL-2.0-only |
| `reline`               | Ruby               |
| `rexml`                | BSD-2-Clause       |
| `rubyzip`              | BSD-2-Clause       |
| `securerandom`         | Ruby, BSD-2-Clause |
| `solid_cable`          | MIT                |
| `sqlite3`              | BSD-3-Clause       |
| `thor`                 | MIT                |
| `timeout`              | Ruby, BSD-2-Clause |
| `tsort`                | Ruby, BSD-2-Clause |
| `turbo-rails`          | MIT                |
| `tzinfo`               | MIT                |
| `uri`                  | Ruby, BSD-2-Clause |
| `useragent`            | MIT                |
| `view_component`       | MIT                |
| `websocket-driver`     | Apache-2.0         |
| `websocket-extensions` | Apache-2.0         |
| `zeitwerk`             | MIT                |

## JavaScript Packages

| Package                            | License                         |
| ---------------------------------- | ------------------------------- |
| `@fontsource-variable/inter`       | OFL-1.1                         |
| `@fontsource-variable/roboto-mono` | OFL-1.1                         |
| `@fortawesome/fontawesome-free`    | (CC-BY-4.0 AND OFL-1.1 AND MIT) |
| `@hotwired/stimulus`               | MIT                             |
| `@hotwired/turbo`                  | MIT                             |
| `@hotwired/turbo-rails`            | MIT                             |
| `@rails/actioncable`               | MIT                             |
| `highlight.js`                     | BSD-3-Clause                    |
| `stimulus-vite-helpers`            | MIT                             |
| `survey-core`                      | MIT                             |
| `survey-js-ui`                     | MIT                             |
