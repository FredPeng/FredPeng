<?php
/**
 * Database tables and fast lookups used at request time.
 *
 * @package Sophie_Recommendations
 */

defined( 'ABSPATH' ) || exit;

final class Sophie_Rec_Store {

	const DB_VERSION = 1;

	public static function sim_table(): string {
		global $wpdb;
		return $wpdb->prefix . 'sophie_rec_sim';
	}

	public static function items_table(): string {
		global $wpdb;
		return $wpdb->prefix . 'sophie_rec_items';
	}

	public static function views_table(): string {
		global $wpdb;
		return $wpdb->prefix . 'sophie_rec_views';
	}

	public static function install(): void {
		global $wpdb;
		require_once ABSPATH . 'wp-admin/includes/upgrade.php';
		$charset = $wpdb->get_charset_collate();
		$sim     = self::sim_table();
		$items   = self::items_table();
		$views   = self::views_table();
		// Similar products, top 30 per product.
		dbDelta(
			"CREATE TABLE $sim (
				product_id bigint(20) unsigned NOT NULL,
				related_id bigint(20) unsigned NOT NULL,
				score float NOT NULL,
				PRIMARY KEY  (product_id,related_id)
			) $charset;"
		);
		// Recommendable products: category and trend score.
		dbDelta(
			"CREATE TABLE $items (
				product_id bigint(20) unsigned NOT NULL,
				leaf_cat bigint(20) unsigned NOT NULL DEFAULT 0,
				top_cat bigint(20) unsigned NOT NULL DEFAULT 0,
				trend float NOT NULL DEFAULT 0,
				in_stock tinyint(1) NOT NULL DEFAULT 1,
				PRIMARY KEY  (product_id),
				KEY leaf_trend (leaf_cat,trend),
				KEY top_trend (top_cat,trend),
				KEY trend (trend)
			) $charset;"
		);
		// Anonymous product views (random session number, no personal data).
		dbDelta(
			"CREATE TABLE $views (
				id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
				sid int(10) unsigned NOT NULL,
				product_id bigint(20) unsigned NOT NULL,
				ts int(10) unsigned NOT NULL,
				PRIMARY KEY  (id),
				KEY sid_ts (sid,ts),
				KEY ts (ts)
			) $charset;"
		);
		update_option( 'sophie_rec_db_version', self::DB_VERSION, false );
	}

	public static function maybe_upgrade(): void {
		if ( (int) get_option( 'sophie_rec_db_version' ) < self::DB_VERSION ) {
			self::install();
		}
	}

	/**
	 * Similar products for a set of products: [id => [related => score]].
	 */
	public static function sims_for( array $ids ): array {
		global $wpdb;
		$ids = array_slice( array_filter( array_map( 'absint', $ids ) ), 0, 40 );
		if ( ! $ids ) {
			return array();
		}
		$table = self::sim_table();
		$in    = implode( ',', $ids );
		$rows  = $wpdb->get_results( "SELECT product_id, related_id, score FROM $table WHERE product_id IN ($in)", ARRAY_N ); // phpcs:ignore WordPress.DB
		$out   = array();
		foreach ( (array) $rows as $r ) {
			$out[ (int) $r[0] ][ (int) $r[1] ] = (float) $r[2];
		}
		return $out;
	}

	/**
	 * Category info for products that are currently recommendable.
	 *
	 * @return array [id => ['leaf' => int, 'top' => int]]
	 */
	public static function items_for( array $ids, bool $only_in_stock = false ): array {
		global $wpdb;
		$ids = array_filter( array_map( 'absint', $ids ) );
		if ( ! $ids ) {
			return array();
		}
		$table = self::items_table();
		$in    = implode( ',', array_unique( $ids ) );
		$where = $only_in_stock ? ' AND in_stock = 1' : '';
		$rows  = $wpdb->get_results( "SELECT product_id, leaf_cat, top_cat FROM $table WHERE product_id IN ($in)$where", ARRAY_N ); // phpcs:ignore WordPress.DB
		$out   = array();
		foreach ( (array) $rows as $r ) {
			$out[ (int) $r[0] ] = array(
				'leaf' => (int) $r[1],
				'top'  => (int) $r[2],
			);
		}
		return $out;
	}

	/** Top trending in-stock products of a category: [id => trend]. */
	public static function category_trending( int $cat, bool $top_level, int $limit = 30 ): array {
		global $wpdb;
		$table = self::items_table();
		$col   = $top_level ? 'top_cat' : 'leaf_cat';
		$rows  = $wpdb->get_results( $wpdb->prepare( "SELECT product_id, trend FROM $table WHERE $col = %d AND in_stock = 1 ORDER BY trend DESC LIMIT %d", $cat, $limit ), ARRAY_N ); // phpcs:ignore WordPress.DB
		$out   = array();
		foreach ( (array) $rows as $r ) {
			$out[ (int) $r[0] ] = (float) $r[1];
		}
		return $out;
	}

	/** Global trending in-stock products: [id => trend], cached for an hour. */
	public static function trending( int $limit = 60 ): array {
		$key    = 'trending_' . $limit . '_' . self::model_version();
		$cached = wp_cache_get( $key, 'sophie_rec' );
		if ( is_array( $cached ) ) {
			return $cached;
		}
		global $wpdb;
		$table = self::items_table();
		$rows  = $wpdb->get_results( $wpdb->prepare( "SELECT product_id, trend FROM $table WHERE in_stock = 1 AND trend > 0 ORDER BY trend DESC LIMIT %d", $limit ), ARRAY_N ); // phpcs:ignore WordPress.DB
		$out   = array();
		foreach ( (array) $rows as $r ) {
			$out[ (int) $r[0] ] = (float) $r[1];
		}
		wp_cache_set( $key, $out, 'sophie_rec', HOUR_IN_SECONDS );
		return $out;
	}

	/** Changes whenever the model is rebuilt (used in cache keys / URLs). */
	public static function model_version(): int {
		return (int) get_option( 'sophie_rec_model_version', 0 );
	}

	public static function set_in_stock( int $product_id, bool $in_stock ): void {
		global $wpdb;
		$wpdb->update( self::items_table(), array( 'in_stock' => $in_stock ? 1 : 0 ), array( 'product_id' => $product_id ) ); // phpcs:ignore WordPress.DB
	}

	/** Records anonymous views. */
	public static function insert_views( int $sid, array $product_ids ): int {
		global $wpdb;
		$ids = array_slice( array_unique( array_filter( array_map( 'absint', $product_ids ) ) ), 0, 20 );
		if ( ! $sid || ! $ids ) {
			return 0;
		}
		$now    = time();
		$values = array();
		foreach ( $ids as $i => $id ) {
			$values[] = $wpdb->prepare( '(%d,%d,%d)', $sid, $id, $now - $i );
		}
		$table = self::views_table();
		return (int) $wpdb->query( "INSERT INTO $table (sid, product_id, ts) VALUES " . implode( ',', $values ) ); // phpcs:ignore WordPress.DB
	}
}
