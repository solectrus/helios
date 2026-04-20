# Rack middleware that blocks all requests with a fail screen
# when critical startup prerequisites are not met.
#
# Runs before ActiveRecord, so no database access is needed.
# The health check endpoint (/up) is excluded so that container
# orchestration tools can still probe liveness.
class StartupCheckMiddleware
  HEALTH_PATH = '/up'.freeze

  def initialize(app)
    @app = app
    @failures = nil
    @checked = false
  end

  def call(env)
    run_checks_once

    if @failures.any? && env[Rack::PATH_INFO] != HEALTH_PATH
      render_fail_screen
    else
      @app.call(env)
    end
  end

  private

  def run_checks_once
    return if @checked

    @failures = StartupCheck.run
    @checked = true

    @failures.each do |check|
      Rails.logger.error("[StartupCheck] #{check.name}: #{check.message}")
    end
  end

  def render_fail_screen
    [503, { 'content-type' => 'text/html; charset=utf-8' }, [html_body]]
  end

  def html_body # rubocop:disable Metrics/MethodLength
    checks_html = @failures.map do |check|
      <<~HTML
        <div class="check fail">
          <span class="icon">&#10007;</span>
          <div>
            <strong>#{escape(check.name)}</strong>
            <p>#{escape(check.message)}</p>
          </div>
        </div>
      HTML
    end.join

    <<~HTML
      <!doctype html>
      <html lang="en">
        <head>
          <title>HELIOS – Startup Failed</title>
          <meta charset="utf-8">
          <meta name="viewport" content="initial-scale=1, width=device-width">
          <meta name="robots" content="noindex, nofollow">
          #{style_tag}
        </head>
        <body>
          <main>
            <header>
              #{logo_svg}
            </header>
            <article>
              <h1>Startup Failed</h1>
              <p class="subtitle">HELIOS cannot start because of configuration problems.<br>
              Please check your <code>compose.yaml</code> and try again.</p>
              #{checks_html}
            </article>
          </main>
        </body>
      </html>
    HTML
  end

  def escape(text)
    Rack::Utils.escape_html(text)
  end

  def logo_svg
    <<~SVG
      <svg viewBox="0 0 1200 1200" xmlns="http://www.w3.org/2000/svg">
        <path
          class="logo"
          stroke-width="25"
          stroke-linejoin="round"
          d="m747.775 44.2c245.861 65.31 427.225 289.542 427.225 555.8 0 314.622-253.236 570.56-566.779 574.94 41.679-83.59 94.576-189.745 151.182-303.438 149.04-299.567 230.764-466.538 231.549-473.168 1.31-9.085.524-11.05-8.905-20.381-17.026-17.188-11.002-17.924-205.095 26.765-94.296 21.854-173.662 40.27-176.019 41.006-2.881.737-4.715 0-4.715-1.964 0-1.719 34.313-89.87 75.961-195.946 41.909-105.831 75.961-195.946 75.961-199.63 0-1.331-.124-2.661-.365-3.984zm-367.512 24.346c-39.478 141.435-171.707 647.798-171.707 660.539 0 16.943 17.026 31.921 36.147 31.921 4.191 0 88.272-18.907 186.497-41.743 98.487-23.081 179.686-41.497 180.734-41.252 1.048.491-37.456 151.503-85.39 335.909-14.918 57.08-27.922 107.14-38.984 150.07-263.581-52.32-462.56-285.102-462.56-563.99 0-239.537 146.788-445.06 355.263-531.454z"
        />
      </svg>
    SVG
  end

  def style_tag
    <<~HTML
      <style>
        *, *::before, *::after { box-sizing: border-box; }
        * { margin: 0; }
        html { font-size: 16px; }

        body {
          background: #FFF;
          color: #261B23;
          display: grid;
          font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, Aptos, Roboto, "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif;
          font-size: clamp(1rem, 2.5vw, 1.5rem);
          -webkit-font-smoothing: antialiased;
          line-height: 1.4;
          min-height: 100dvh;
          place-items: center;
        }

        @media (prefers-color-scheme: dark) {
          body { background: #101010; color: #e0e0e0; }
          .logo { fill: #e0e0e0; }
          code { background: #2c2c2c; }
          .check { background: #1a1a1a; border-color: #333; }
        }

        .logo { fill: #B8860B; }

        main {
          display: grid;
          gap: 1.5em;
          padding: 2em;
          place-items: center;
          text-align: center;
          max-width: 40em;
        }

        main header { width: min(100%, 4em); }
        main header svg { height: auto; max-width: 100%; width: 100%; }

        h1 {
          font-size: 1.25em;
          font-weight: 700;
          color: #d30001;
        }

        @media (prefers-color-scheme: dark) {
          h1 { color: #FF6161; }
        }

        .subtitle {
          font-size: 0.75em;
          margin-top: 0.5em;
          opacity: 0.8;
        }

        code {
          background: #f0eff0;
          padding: 0.1em 0.4em;
          border-radius: 0.25em;
          font-size: 0.9em;
        }

        .check {
          display: flex;
          gap: 0.75em;
          align-items: flex-start;
          text-align: left;
          padding: 0.75em 1em;
          border: 1px solid #e0e0e0;
          border-radius: 0.5em;
          width: 100%;
          margin-top: 0.5em;
        }

        .check .icon {
          font-size: 1.2em;
          line-height: 1;
          flex-shrink: 0;
        }

        .check.fail .icon { color: #d30001; }
        @media (prefers-color-scheme: dark) {
          .check.fail .icon { color: #FF6161; }
        }

        .check strong {
          display: block;
          font-size: 0.8em;
        }

        .check p {
          font-size: 0.65em;
          opacity: 0.8;
          margin-top: 0.15em;
        }
      </style>
    HTML
  end
end
