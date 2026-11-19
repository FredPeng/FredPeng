<?php
/**
 * Plugin Name: Sophie App – Store API catalogue cache
 * Description: Caches the read-only WooCommerce Store API catalogue endpoints (products, product, categories) that the mobile app uses, so app traffic does not slow down the website. Cart, checkout, search and logged-in requests are never cached.
 * Version: 1.0.0
 * Author: Fred Peng
 *
 * Install: copy this file to wp-content/mu-plugins/ (create the folder if needed).
 * Must-use plugins load automatically; nothing to activate.
 *
 * Check: curl -sI "https://sophie.co.ke/wp-json/wc/store/v1/products?per_page=1" | grep -i x-sophie-cache
 * (MISS on the first request, HIT on the next ones).
 */

defined( 'ABSPATH' ) || exit;

/** Seconds a cached response stays fresh. Any product, stock or category change clears it immediately. */
if ( ! defined( 'SOPHIE_APP_CACHE_TTL' ) ) {
	define( 'SOPHIE_APP_CACHE_TTL', 600 );
}

/**
 * Cache key for a request, or null if the request must not be cached.
 */
function sophie_app_cache_key( $request ) {
	if ( ! $request instanceof WP_REST_Request || 'GET' !== $request->get_method() ) {
		return null;
	}
	$route = $request->get_route();
	if ( ! preg_match( '#^/wc/store(?:/v\d+)?/products(?:/categories|/\d+)?$#', $route ) ) {
		return null; // cart, checkout, everything else: never cached.
	}
	$params = $request->get_query_params();
	if ( ! empty( $params['search'] ) ) {
		return null; // free-text searches would create unbounded cache entries.
	}
	if ( is_user_logged_in() ) {
		return null; // role-based prices, private/draft products.
	}
	ksort( $params );
	$version = (int) get_option( 'sophie_app_cache_ver', 1 );
	return md5( $version . '|' . $route . '|' . wp_json_encode( $params ) );
}

function sophie_app_cache_dir() {
	return WP_CONTENT_DIR . '/cache/sophie-app';
}

function sophie_app_cache_get( $key ) {
	if ( wp_using_ext_object_cache() ) {
		$value = wp_cache_get( $key, 'sophie_app' );
		return is_array( $value ) ? $value : null;
	}
	$file = sophie_app_cache_dir() . '/' . $key . '.cache';
	if ( ! is_readable( $file ) || filemtime( $file ) < time() - SOPHIE_APP_CACHE_TTL ) {
		return null;
	}
	$value = @unserialize( (string) file_get_contents( $file ), array( 'allowed_classes' => array( 'stdClass' ) ) );
	return is_array( $value ) ? $value : null;
}

function sophie_app_cache_set( $key, array $value ) {
	if ( wp_using_ext_object_cache() ) {
		wp_cache_set( $key, $value, 'sophie_app', SOPHIE_APP_CACHE_TTL );
		return;
	}
	$dir = sophie_app_cache_dir();
	if ( ! is_dir( $dir ) && ! wp_mkdir_p( $dir ) ) {
		return;
	}
	if ( ! file_exists( $dir . '/index.php' ) ) {
		@file_put_contents( $dir . '/index.php', "<?php // Silence is golden.\n" );
	}
	$tmp = $dir . '/' . $key . '.' . wp_generate_password( 6, false ) . '.tmp';
	if ( false !== @file_put_contents( $tmp, serialize( $value ) ) ) {
		@rename( $tmp, $dir . '/' . $key . '.cache' ); // atomic: readers never see half a file.
	}
}

/** Serve a cached response before WooCommerce runs its product queries. */
add_filter(
	'rest_pre_dispatch',
	function ( $result, $server, $request ) {
		if ( null !== $result ) {
			return $result;
		}
		$key = sophie_app_cache_key( $request );
		$hit = $key ? sophie_app_cache_get( $key ) : null;
		if ( ! $hit ) {
			return $result;
		}
		$response = new WP_REST_Response( $hit['data'], 200 );
		foreach ( (array) $hit['headers'] as $name => $value ) {
			$response->header( $name, $value );
		}
		$response->header( 'X-Sophie-Cache', 'HIT' );
		return $response;
	},
	10,
	3
);

/** Store fresh responses, and let Cloudflare cache them briefly too. */
add_filter(
	'rest_post_dispatch',
	function ( $response, $server, $request ) {
		if ( ! $response instanceof WP_REST_Response || 200 !== $response->get_status() ) {
			return $response;
		}
		$key = sophie_app_cache_key( $request );
		if ( ! $key ) {
			return $response;
		}
		$headers = $response->get_headers();
		if ( ( $headers['X-Sophie-Cache'] ?? '' ) !== 'HIT' ) {
			sophie_app_cache_set(
				$key,
				array(
					'data'    => $response->get_data(),
					'headers' => array_intersect_key( $headers, array_flip( array( 'X-WP-Total', 'X-WP-TotalPages' ) ) ),
				)
			);
			$response->header( 'X-Sophie-Cache', 'MISS' );
		}
		$response->header( 'Cache-Control', 'public, max-age=60, s-maxage=300' );
		return $response;
	},
	999,
	3
);

/** Any catalogue change invalidates every cached entry (new version = new keys). */
function sophie_app_cache_flush() {
	static $done = false; // once per request, e.g. bulk edits.
	if ( $done ) {
		return;
	}
	$done = true;
	update_option( 'sophie_app_cache_ver', (int) get_option( 'sophie_app_cache_ver', 1 ) + 1, false );
}

foreach ( array(
	'woocommerce_new_product',
	'woocommerce_update_product',
	'woocommerce_delete_product',
	'woocommerce_trash_product',
	'woocommerce_update_product_variation',
	'woocommerce_product_set_stock',
	'woocommerce_variation_set_stock',
	'woocommerce_product_set_stock_status',
	'woocommerce_variation_set_stock_status',
	'wc_after_products_starting_sales',
	'wc_after_products_ending_sales',
	'created_product_cat',
	'edited_product_cat',
	'delete_product_cat',
) as $sophie_app_hook ) {
	add_action( $sophie_app_hook, 'sophie_app_cache_flush' );
}

/** Daily clean-up of expired cache files. */
add_action(
	'init',
	function () {
		if ( ! wp_next_scheduled( 'sophie_app_cache_gc' ) ) {
			wp_schedule_event( time() + HOUR_IN_SECONDS, 'daily', 'sophie_app_cache_gc' );
		}
	}
);
add_action(
	'sophie_app_cache_gc',
	function () {
		foreach ( (array) glob( sophie_app_cache_dir() . '/*.{cache,tmp}', GLOB_BRACE ) as $file ) {
			if ( is_file( $file ) && filemtime( $file ) < time() - DAY_IN_SECONDS ) {
				@unlink( $file );
			}
		}
	}
);
