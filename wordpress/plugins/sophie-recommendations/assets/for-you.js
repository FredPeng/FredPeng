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
	function load(section) {
		var grid = section.querySelector('.sophie-for-you__grid');
		var h = (get(HISTORY) || []).slice(0, 10);
		var p = (get(BOUGHT) || []).slice(0, 10);
		// Only the visitor's history is in the URL: new visitors all share one
		// cacheable URL, and the same history always gets the same answer.
		var url = cfg.ajax + '?action=sophie_rec_for_you' +
			'&n=' + encodeURIComponent(section.getAttribute('data-limit') || 8) +
			'&c=' + encodeURIComponent(section.getAttribute('data-columns') || 4) +
			'&h=' + h.join(',') + '&p=' + p.join(',') + '&v=' + (cfg.version || 0);
		fetch(url, { credentials: 'omit' })
			.then(function (r) { return r.ok ? r.text() : ''; })
			.then(function (html) {
				if (!html || html.replace(/\s/g, '').length < 20) { section.style.display = 'none'; return; }
				grid.innerHTML = html;
				grid.removeAttribute('aria-busy');
				section.classList.add('is-loaded');
				if (window.jQuery) {
					// Let the theme (lazy images, wishlist/quick-view buttons) initialise the new cards.
					window.jQuery(document.body).trigger('sophie_for_you_loaded', [section]).trigger('post-load');
					window.jQuery(window).trigger('resize').trigger('scroll');
				}
			})
			.catch(function () { section.style.display = 'none'; });
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
