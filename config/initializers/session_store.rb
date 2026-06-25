# Persist the login across browser/PWA restarts.
#
# Without `expire_after` the session lives in a transient browser-session
# cookie that iOS drops whenever it evicts an installed PWA from memory
# (typically after a few days of inactivity), forcing a re-login. A fixed
# expiry turns it into a persistent cookie that survives those evictions.
#
# The key is pinned to Rails' historical default (`_helios_session`) so
# existing sessions stay valid after this change.
Rails.application.config.session_store :cookie_store,
                                       key: '_helios_session',
                                       expire_after: 30.days
