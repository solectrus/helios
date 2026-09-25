# Never build assets from within Rails. Development gets them from the Vite
# dev server started by bin/dev, test uses assets pre-built via ci.rb or
# `bunx vite build --mode test`.
RailsVite.config.auto_build = false
