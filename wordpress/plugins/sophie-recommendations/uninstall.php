<?php
/**
 * Removes the plugin's tables and options when it is deleted.
 *
 * @package Sophie_Recommendations
 */

defined( 'WP_UNINSTALL_PLUGIN' ) || exit;

global $wpdb;
foreach ( array( 'sophie_rec_sim', 'sophie_rec_items', 'sophie_rec_views' ) as $t ) {
	$wpdb->query( "DROP TABLE IF EXISTS {$wpdb->prefix}{$t}, {$wpdb->prefix}{$t}_new, {$wpdb->prefix}{$t}_old" ); // phpcs:ignore WordPress.DB
}
foreach ( array( 'sophie_rec_settings', 'sophie_rec_stats', 'sophie_rec_model_version', 'sophie_rec_db_version', 'sophie_rec_trending_at', 'sophie_rec_page_id' ) as $o ) {
	delete_option( $o );
}
wp_clear_scheduled_hook( 'sophie_rec_build' );
wp_clear_scheduled_hook( 'sophie_rec_trending' );
