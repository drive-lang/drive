(function () {
	let size = window.innerWidth + 'x' + window.innerHeight;
	if (document.cookie.indexOf('#{BROWSER_VIEW_SIZE}=' + size) === -1) {
		document.cookie = '#{BROWSER_VIEW_SIZE}=' + size + '; path=/'
		window.location = ''
	}

	document.addEventListener('click', async (event) => {
		const element = event.target.closest('a[href], button, input:not([type="hidden"]), select, textarea, summary, [data-backend-onclick]')

		if (!element) return
		if (!element.hasAttribute('data-backend-onclick')) return
		const object_id = element.dataset.driveOnclick

		event.preventDefault()
		event.stopPropagation()

		const inputs = {};
		document.querySelectorAll('[data-backend-id]').forEach(el => {
			if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') {
				inputs[el.dataset.driveId] = el.value;
			}
		});

		const url = `/onclick/${object_id}`
		const response = await fetch(url, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
			},
			body: JSON.stringify({inputs})
		})

        function update_target_html(target, html) {
            if (!html) return;

            const node = target || document.documentElement;
            const update = () => { node.outerHTML = html; };

            if (document.startViewTransition) {
                document.startViewTransition(update);
            } else {
                update();
            }
        }

		const body = await response.text()
		const target_id = response.headers.get('X-Backend-Target-Id')
		const target = document.getElementById(target_id)
        update_target_html(target, body)
	})
})()
