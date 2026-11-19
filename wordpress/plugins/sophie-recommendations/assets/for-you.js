/**
 * Sophie Recommendations: remembers what this browser looked at (localStorage,
 * nothing personal), sends anonymous views in small batches, and loads the
 * "Products For You" section when it comes near the screen.
 */
(function () {
	'use strict';
	var cfg = window.sophieRecConfig || {};
	var page = window.sophieRecPage || {};
	var HISTORY = 'sophie_rec_h', BOUGHT = 'sophie_rec_p', QUEUE = 'sophie_rec_q', SID = 'sophie_rec_sid';

	function get(k) { try { return JSON.parse(window.localStorage.getItem(k) || 'null'); } catch (e) { return null; } }
	function set(k, v) { try { window.localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private mode */ } }
	function push(key, id, max) {
		id = parseInt(id, 10);
		if (!id) { return; }
		var list = (get(key) || []).filter(function (x) { return x !== id; });
		list.unshift(id);
		set(key, list.slice(0, max));
	}

	var sid = get(SID);
	if (!sid) { sid = 1 + Math.floor(Math.random() * 4294967290); set(SID, sid); }

	// ---- learning ------------------------------------------------------------
	// Views are queued and sent together during a normal page load (never on
	// page unload, where browsers may drop requests): one request per 3
	// product views, or the leftovers once they are 30 minutes old.
	function flush() {
		var q = get(QUEUE) || [];
		var age = Date.now() - (get(QUEUE + 't') || Date.now());
		if (!cfg.track || !q.length || !navigator.sendBeacon) { return; }
		if (q.length < 3 && age < 1800000) { return; }
		// text/plain avoids a CORS preflight.
		if (navigator.sendBeacon(cfg.track, new Blob([JSON.stringify({ sid: sid, items: q })], { type: 'text/plain' }))) {
			set(QUEUE, []);
			set(QUEUE + 't', null);
		}
	}
	if (page.view) {
		push(HISTORY, page.view, 20);
		var q = get(QUEUE) || [];
		if (q[0] !== page.view) {
			if (!q.length) { set(QUEUE + 't', Date.now()); }
			q.unshift(page.view);
			set(QUEUE, q.slice(0, 20));
		}
	}
	if (page.bought) { page.bought.forEach(function (id) { push(BOUGHT, id, 20); }); }
	flush();

	// Add to cart (archive buttons and single product form) is a strong signal.
	document.addEventListener('click', function (e) {
		var el = e.target && e.target.closest ? e.target.closest('.add_to_cart_button[data-product_id], .single_add_to_cart_button') : null;
		if (!el) { return; }
		push(HISTORY, el.getAttribute('data-product_id') || el.value || page.view, 20);
	}, true);

	// ---- the section ---------------------------------------------------------
	function url(section, offset) {
		var h = (get(HISTORY) || []).slice(0, 10);
		var p = (get(BOUGHT) || []).slice(0, 10);
		// Only the visitor's history is in the URL: new visitors all share one
		// cacheable URL, and the same history always gets the same answer.
		return cfg.ajax + '?action=sophie_rec_for_you' +
			'&n=' + encodeURIComponent(section.getAttribute('data-limit') || 4) +
			'&o=' + offset +
			'&c=' + encodeURIComponent(section.getAttribute('data-columns') || 4) +
			'&h=' + h.join(',') + '&p=' + p.join(',') + '&v=' + (cfg.version || 0);
	}

	function themeRefresh(section) {
		if (window.jQuery) {
			// Let the theme (lazy images, wishlist / quick-view buttons) initialise the new cards.
			window.jQuery(document.body).trigger('sophie_for_you_loaded', [section]).trigger('post-load');
			window.jQuery(window).trigger('resize').trigger('scroll');
		}
	}

	function load(section) {
		var grid = section.querySelector('.sophie-for-you__grid');
		var all = section.getAttribute('data-mode') === 'all';
		var per = parseInt(section.getAttribute('data-limit'), 10) || 4;
		var more = section.querySelector('.sophie-for-you__more');
		var offset = 0, busy = false, done = false, sentinel = null;

		function next() {
			if (busy || done) { return; }
			busy = true;
			if (more) { more.querySelector('button').disabled = true; }
			fetch(url(section, offset), { credentials: 'omit' })
				.then(function (r) {
					var hasMore = r.headers.get('X-Sophie-More') === '1';
					return r.ok ? r.text().then(function (t) { return { html: t, more: hasMore }; }) : { html: '', more: false };
				})
				.then(function (res) {
					var empty = !res.html || res.html.replace(/\s/g, '').length < 20;
					if (offset === 0) {
						if (empty) { section.style.display = 'none'; done = true; return; }
						grid.innerHTML = '';
						grid.removeAttribute('aria-busy');
						section.classList.add('is-loaded');
					}
					if (!empty) { grid.insertAdjacentHTML('beforeend', res.html); }
					offset += per;
					done = !all || !res.more || empty;
					themeRefresh(section);
				})
				.catch(function () { if (offset === 0) { section.style.display = 'none'; } done = true; })
				.then(function () {
					busy = false;
					if (!more) { return; }
					more.hidden = done;
					more.querySelector('button').disabled = false;
					if (done && sentinel) { sentinel.disconnect(); }
				});
		}

		if (all && more) {
			more.querySelector('button').addEventListener('click', next);
			if ('IntersectionObserver' in window) {
				// Infinite scroll: load the next page before the visitor reaches the end.
				sentinel = new IntersectionObserver(function (entries) {
					if (entries[0].isIntersecting && offset > 0) { next(); }
				}, { rootMargin: '800px 0px' });
				sentinel.observe(more);
			}
		}
		next();
	}

	function init() {
		var sections = document.querySelectorAll('.sophie-for-you');
		Array.prototype.forEach.call(sections, function (section) {
			if (!('IntersectionObserver' in window)) { load(section); return; }
			var io = new IntersectionObserver(function (entries) {
				if (entries[0].isIntersecting) { io.disconnect(); load(section); }
			}, { rootMargin: '600px 0px' });
			io.observe(section);
		});
	}
	if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', init); } else { init(); }
}());
