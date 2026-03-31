# Enable gzip and brotli compression
Rails.application.config.middleware.insert(0, Rack::Brotli)
Rails.application.config.middleware.insert(0, Rack::Deflater)
