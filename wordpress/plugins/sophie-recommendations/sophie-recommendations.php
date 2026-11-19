<?php
/**
 * Plugin Name:       Sophie Recommendations – Products For You
 * Description:       Personalised "Products For You" recommendations for WooCommerce: learns from what customers buy together and browse together, ranks per visitor in the browser-cache-friendly way, and works behind page caches and Cloudflare. Shortcode: [sophie_for_you]
 * Version:           1.1.0
 * Requires at least: 6.2
 * Requires PHP:      7.4
 * Author:            Fred Peng
 * Text Domain:       sophie-rec
 * WC requires at least: 7.0
 *
 * @package Sophie_Recommendations
 */

defined( 'ABSPATH' ) || exit;

define( 'SOPHIE_REC_VERSION', '1.1.0' );
define( 'SOPHIE_REC_FILE', __FILE__ );
define( 'SOPHIE_REC_DIR', plugin_dir_path( __FILE__ ) );
define( 'SOPHIE_REC_URL', plugin_dir_url( __FILE__ ) );

require_once SOPHIE_REC_DIR . 'includes/class-model.php';
require_once SOPHIE_REC_DIR . 'includes/class-store.php';
require_once SOPHIE_REC_DIR . 'includes/class-builder.php';
require_once SOPHIE_REC_DIR . 'includes/class-recommender.php';
require_once SOPHIE_REC_DIR . 'includes/class-frontend.php';
require_once SOPHIE_REC_DIR . 'includes/class-rest.php';
require_once SOPHIE_REC_DIR . 'includes/class-admin.php';

/** Settings with defaults. */
function sophie_rec_settings(): array {
	return wp_parse_args(
		(array) get_option( 'sophie_rec_settings', array() ),
		array(
			'title'           => 'Products For You',
			'limit'           => 4, // home page; the "See all" page shows up to 96.
			'columns'         => 4,
			'tracking'        => 1, // learn "viewed together" from anonymous browsing.
			'related'         => 1, // also improve "Related products" on product pages.
			'exclude_cats'    => '', // comma-separated category ids never recommended.
		)
	);
}

register_activation_hook(
	__FILE__,
	function () {
		Sophie_Rec_Store::install();
		Sophie_Rec_Builder::schedule();
		Sophie_Rec_Admin::ensure_page();
		// First model build shortly after activation, in the background.
		wp_schedule_single_event( time() + 30, 'sophie_rec_build' );
	}
);

register_deactivation_hook(
	__FILE__,
	function () {
		wp_clear_scheduled_hook( 'sophie_rec_build' );
		wp_clear_scheduled_hook( 'sophie_rec_trending' );
	}
);

add_action(
	'plugins_loaded',
	function () {
		if ( ! class_exists( 'WooCommerce' ) ) {
			return;
		}
		Sophie_Rec_Store::maybe_upgrade();
		Sophie_Rec_Builder::init();
		Sophie_Rec_Frontend::init();
		Sophie_Rec_Rest::init();
		if ( is_admin() ) {
			Sophie_Rec_Admin::init();
		}
	}
);

// HPOS compatibility: the plugin only reads analytics lookup tables.
add_action(
	'before_woocommerce_init',
	function () {
		if ( class_exists( \Automattic\WooCommerce\Utilities\FeaturesUtil::class ) ) {
			\Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility( 'custom_order_tables', __FILE__, true );
		}
	}
);
