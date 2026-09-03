// Browser side of live reload. Injected into every HTML response (right after dom.js) ONLY when
// the server runs under Hot_Reloader -- see Interpreter#live_reload. Talks to the matching
// `/_tape/live-reload` endpoint mounted in Interpreter#start_server.
//
// How it works: the endpoint streams one `data: <token>` line, where <token> is unique to the
// running Interpreter. On a hot reload the whole Interpreter is rebuilt, so the token changes.
// We remember the first token we ever see; the moment the stream reports a different one, the
// server we're looking at is stale, so we reload the page.

(function () {
	// Lives at IIFE scope so it survives the manual reconnect below, not just the browser's own
	// automatic EventSource retries.
	let first_token = null

	function connect() {
		const events = new EventSource('/_tape/live-reload')

		events.onmessage = (event) => {
			// First message after any (re)connect establishes the baseline...
			if (first_token === null) {
				first_token = event.data
				return
			}
			// ...and any later token means a fresh Interpreter is now serving -- reload to pick up
			// the new markup / CSS / routes.
			if (event.data !== first_token) location.reload()
		}

		events.onerror = () => {
			// A transient drop (server mid-restart) leaves readyState === CONNECTING and the browser
			// retries on its own using the `retry:` interval the endpoint sends -- nothing to do.
			// Only a permanent failure closes the stream for good, and that's when we start over.
			if (events.readyState === EventSource.CLOSED) setTimeout(connect, 300)
		}
	}

	connect()
})()
