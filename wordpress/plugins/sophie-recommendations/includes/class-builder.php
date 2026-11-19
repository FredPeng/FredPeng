<?php
/**
 * Offline model build (WP-Cron): nightly similarity, hourly trending.
 *
 * Reads WooCommerce's analytics lookup table (wc_order_product_lookup) when
 * available, otherwise order line items directly. Writes into new tables and
 * swaps them in with one atomic RENAME, so visitors never see a half-built
 * model and the site is never locked.
 *
 * @package Sophie_Recommendations
 */

defined( 'ABSPATH' ) || exit;

final class Sophie_Rec_Builder {

	const CHUNK            = 20000;
	const VIEW_WEIGHT      = 0.4;   // "viewed together" counts less than "bought together".
	const SESSION_GAP      = 1800;  // 30 min of inactivity starts a new browsing session.
	const MAX_PAIRS        = 1500000; // memory guard (pair updates), see also memory_ok().
	const PAID_STATUSES    = array( 'wc-completed', 'wc-processing', 'wc-on-hold' );

	private static $pair_count = 0;

	public static function init(): void {
		add_action( 'sophie_rec_build', array( __CLASS__, 'build' ) );
		add_action( 'sophie_rec_trending', array( __CLASS__, 'build_items' ) );
		add_action( 'init', array( __CLASS__, 'schedule' ) );
		// Keep stock status current between builds.
		add_action(
			'woocommerce_product_set_stock_status',
			function ( $product_id, $status ) {
				Sophie_Rec_Store::set_in_stock( (int) $product_id, 'outofstock' !== $status );
			},
			10,
			2
		);
	}

	public static function schedule(): void {
		if ( ! wp_next_scheduled( 'sophie_rec_build' ) ) {
			// 03:00 site time, when the shop is quiet.
			$next = strtotime( 'tomorrow 03:00', current_time( 'timestamp' ) ) - (int) ( get_option( 'gmt_offset' ) * HOUR_IN_SECONDS );
			wp_schedule_event( $next, 'daily', 'sophie_rec_build' );
		}
		if ( ! wp_next_scheduled( 'sophie_rec_trending' ) ) {
			wp_schedule_event( time() + HOUR_IN_SECONDS, 'hourly', 'sophie_rec_trending' );
		}
	}

	/** Full rebuild. Returns stats. */
	public static function build(): array {
		if ( get_transient( 'sophie_rec_building' ) ) {
			return array( 'error' => 'A build is already running.' );
		}
		set_transient( 'sophie_rec_building', 1, 15 * MINUTE_IN_SECONDS );
		wp_raise_memory_limit( 'admin' );
		if ( function_exists( 'set_time_limit' ) ) {
			@set_time_limit( 600 ); // phpcs:ignore
		}
		$start = microtime( true );
		try {
			$items = self::build_items();

			self::$pair_count = 0;
			$buy_pairs        = array();
			$buy_counts       = array();
			$orders           = self::collect_purchases( $buy_pairs, $buy_counts );
			// Reduce each source to its top neighbours straight away (lower peak memory).
			$buy_sims = Sophie_Rec_Model::blend_top_k( array( array( Sophie_Rec_Model::similarities( $buy_pairs, $buy_counts ), 1.0 ) ), 60 );
			unset( $buy_pairs, $buy_counts );

			$view_pairs  = array();
			$view_counts = array();
			$sessions    = self::collect_views( $view_pairs, $view_counts );
			$view_sims   = Sophie_Rec_Model::blend_top_k( array( array( Sophie_Rec_Model::similarities( $view_pairs, $view_counts ), 1.0 ) ), 60 );
			unset( $view_pairs, $view_counts );

			$top = Sophie_Rec_Model::blend_top_k(
				array( array( $buy_sims, 1.0 ), array( $view_sims, self::VIEW_WEIGHT ) ),
				60 // filter below, keep 30
			);
			$rows = self::write_sims( $top, $items );
			self::prune_views();

			$stats = array(
				'built_at'      => time(),
				'seconds'       => round( microtime( true ) - $start, 1 ),
				'products'      => count( $items ),
				'with_similar'  => count( $top ),
				'similar_rows'  => $rows,
				'baskets'       => $orders,
				'sessions'      => $sessions,
				'source'        => self::has_lookup() ? 'analytics' : 'orders',
				'memory_mb'     => round( memory_get_peak_usage() / 1048576 ),
				'truncated'     => self::$pair_count >= self::MAX_PAIRS || ! self::memory_ok(),
			);
			update_option( 'sophie_rec_stats', $stats, false );
			update_option( 'sophie_rec_model_version', time(), false );
			return $stats;
		} finally {
			delete_transient( 'sophie_rec_building' );
		}
	}

	// ------------------------------------------------------------- products

	/**
	 * Rebuilds the recommendable-products table (categories, stock, trend).
	 * Cheap enough to run hourly.
	 *
	 * @return array set of recommendable product ids [id => true].
	 */
	public static function build_items(): array {
		global $wpdb;
		$settings = sophie_rec_settings();

		// Category tree.
		$parents = array();
		foreach ( (array) $wpdb->get_results( "SELECT term_id, parent FROM {$wpdb->term_taxonomy} WHERE taxonomy = 'product_cat'", ARRAY_N ) as $r ) {
			$parents[ (int) $r[0] ] = (int) $r[1];
		}
		$excluded_cats = array_filter( array_map( 'absint', explode( ',', (string) $settings['exclude_cats'] ) ) );

		// Hidden and out-of-stock products are flagged with product_visibility terms.
		$hidden_tt = self::visibility_tt( 'exclude-from-catalog' );
		$oos_tt    = self::visibility_tt( 'outofstock' );
		$hidden    = $hidden_tt ? array_flip( $wpdb->get_col( $wpdb->prepare( "SELECT object_id FROM {$wpdb->term_relationships} WHERE term_taxonomy_id = %d", $hidden_tt ) ) ) : array();
		$oos       = $oos_tt ? array_flip( $wpdb->get_col( $wpdb->prepare( "SELECT object_id FROM {$wpdb->term_relationships} WHERE term_taxonomy_id = %d", $oos_tt ) ) ) : array();

		$cats = array();
		$rows = $wpdb->get_results(
			"SELECT tr.object_id, tt.term_id FROM {$wpdb->term_relationships} tr
			 JOIN {$wpdb->term_taxonomy} tt ON tt.term_taxonomy_id = tr.term_taxonomy_id
			 JOIN {$wpdb->posts} p ON p.ID = tr.object_id
			 WHERE tt.taxonomy = 'product_cat' AND p.post_type = 'product' AND p.post_status = 'publish' AND p.post_password = ''",
			ARRAY_N
		);
		foreach ( (array) $rows as $r ) {
			$cats[ (int) $r[0] ][] = (int) $r[1];
		}
		$all = $wpdb->get_col( "SELECT ID FROM {$wpdb->posts} WHERE post_type = 'product' AND post_status = 'publish' AND post_password = ''" );

		$trend = self::trend_scores();

		$items = array();
		$data  = array();
		foreach ( $all as $id ) {
			$id = (int) $id;
			if ( isset( $hidden[ $id ] ) ) {
				continue;
			}
			$leaf      = 0;
			$top       = 0;
			$depth_max = -1;
			$skip      = false;
			foreach ( $cats[ $id ] ?? array() as $cat ) {
				$chain = self::ancestors( $cat, $parents );
				if ( array_intersect( $chain, $excluded_cats ) ) {
					$skip = true;
					break;
				}
				if ( count( $chain ) > $depth_max ) {
					$depth_max = count( $chain );
					$leaf      = $cat;
					$top       = end( $chain );
				}
			}
			if ( $skip ) {
				continue;
			}
			$items[ $id ] = true;
			$data[]       = $wpdb->prepare( '(%d,%d,%d,%f,%d)', $id, $leaf, $top, $trend[ $id ] ?? 0, isset( $oos[ $id ] ) ? 0 : 1 );
		}
		self::swap_table( Sophie_Rec_Store::items_table(), '(product_id, leaf_cat, top_cat, trend, in_stock)', $data );
		wp_cache_delete( 'trending_150_' . Sophie_Rec_Store::model_version(), 'sophie_rec' );
		update_option( 'sophie_rec_trending_at', time(), false );
		return $items;
	}

	private static function ancestors( int $cat, array $parents ): array {
		$chain = array( $cat );
		$guard = 0;
		while ( ! empty( $parents[ $cat ] ) && $guard++ < 20 ) {
			$cat     = $parents[ $cat ];
			$chain[] = $cat;
		}
		return $chain; // leaf first, top-level last.
	}

	private static function visibility_tt( string $slug ): int {
		$term = get_term_by( 'slug', $slug, 'product_visibility' );
		return $term ? (int) $term->term_taxonomy_id : 0;
	}

	/**
	 * Trending = recent sales (14-day half-life-ish decay) + recent views +
	 * all-time sales (small) + a freshness boost for new products.
	 */
	private static function trend_scores(): array {
		global $wpdb;
		$now   = time();
		$score = array();
		$add   = function ( $rows, $mult = 1.0 ) use ( &$score ) {
			foreach ( (array) $rows as $r ) {
				$score[ (int) $r[0] ] = ( $score[ (int) $r[0] ] ?? 0 ) + $mult * (float) $r[1];
			}
		};

		if ( self::has_lookup() ) {
			$statuses = "'" . implode( "','", self::PAID_STATUSES ) . "'";
			$add(
				$wpdb->get_results(
					"SELECT l.product_id, SUM(l.product_qty * EXP(-($now - UNIX_TIMESTAMP(l.date_created)) / 1209600))
					 FROM {$wpdb->prefix}wc_order_product_lookup l
					 JOIN {$wpdb->prefix}wc_order_stats s ON s.order_id = l.order_id
					 WHERE s.status IN ($statuses) AND l.date_created > FROM_UNIXTIME($now - 7776000)
					 GROUP BY l.product_id",
					ARRAY_N
				)
			);
		} else {
			foreach ( self::order_rows( $now - 7776000 ) as $r ) {
				$score[ $r[1] ] = ( $score[ $r[1] ] ?? 0 ) + exp( -( $now - $r[2] ) / 1209600 );
			}
		}

		$views = Sophie_Rec_Store::views_table();
		$add(
			$wpdb->get_results( "SELECT product_id, SUM(EXP(-($now - ts) / 604800)) FROM $views WHERE ts > $now - 1209600 GROUP BY product_id", ARRAY_N ), // phpcs:ignore WordPress.DB
			0.05
		);

		if ( $wpdb->get_var( "SHOW TABLES LIKE '{$wpdb->prefix}wc_product_meta_lookup'" ) ) {
			$add( $wpdb->get_results( "SELECT product_id, LN(1 + total_sales) FROM {$wpdb->prefix}wc_product_meta_lookup WHERE total_sales > 0", ARRAY_N ), 0.05 );
		}

		$add(
			$wpdb->get_results(
				"SELECT ID, EXP(-($now - UNIX_TIMESTAMP(post_date_gmt)) / 604800) FROM {$wpdb->posts}
				 WHERE post_type = 'product' AND post_status = 'publish' AND post_date_gmt > FROM_UNIXTIME($now - 2592000)",
				ARRAY_N
			),
			0.3
		);
		return $score;
	}

	// ------------------------------------------------------------ baskets

	private static function has_lookup(): bool {
		global $wpdb;
		static $has = null;
		if ( null === $has ) {
			$has = (bool) $wpdb->get_var( "SHOW TABLES LIKE '{$wpdb->prefix}wc_order_product_lookup'" )
				&& (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->prefix}wc_order_product_lookup" ) > 0;
		}
		return $has;
	}

	/**
	 * One basket per customer (guests: per order), last 365 days.
	 *
	 * @return int number of baskets.
	 */
	private static function collect_purchases( array &$pairs, array &$counts ): int {
		global $wpdb;
		$now      = time();
		$since    = $now - YEAR_IN_SECONDS;
		$baskets  = 0;
		$cur_key  = null;
		$cur      = array();
		$cur_time = 0;
		$flush    = function () use ( &$pairs, &$counts, &$cur, &$cur_time, &$baskets, $now ) {
			if ( $cur ) {
				$weight = exp( -( $now - $cur_time ) / ( 180 * DAY_IN_SECONDS ) );
				self::add( $pairs, $counts, array_keys( $cur ), $weight );
				$baskets++;
			}
			$cur = array();
		};

		if ( self::has_lookup() ) {
			$statuses = "'" . implode( "','", self::PAID_STATUSES ) . "'";
			$offset   = 0;
			do {
				$rows = $wpdb->get_results(
					$wpdb->prepare(
						"SELECT IF(l.customer_id > 0, l.customer_id, -l.order_id) AS k, l.product_id, UNIX_TIMESTAMP(l.date_created)
						 FROM {$wpdb->prefix}wc_order_product_lookup l
						 JOIN {$wpdb->prefix}wc_order_stats s ON s.order_id = l.order_id
						 WHERE s.status IN ($statuses) AND l.date_created > FROM_UNIXTIME(%d)
						 ORDER BY k, l.date_created DESC LIMIT %d OFFSET %d",
						$since,
						self::CHUNK,
						$offset
					),
					ARRAY_N
				);
				foreach ( (array) $rows as $r ) {
					if ( $r[0] !== $cur_key ) {
						$flush();
						$cur_key  = $r[0];
						$cur_time = (int) $r[2];
					}
					$cur[ (int) $r[1] ] = true;
				}
				$offset += self::CHUNK;
			} while ( $rows && count( $rows ) === self::CHUNK );
		} else {
			foreach ( self::order_rows( $since ) as $r ) {
				if ( $r[0] !== $cur_key ) {
					$flush();
					$cur_key  = $r[0];
					$cur_time = $r[2];
				}
				$cur[ $r[1] ] = true;
			}
		}
		$flush();
		return $baskets;
	}

	/**
	 * Fallback when WooCommerce Analytics tables are empty: order line items.
	 * Basket = order. Works with both HPOS and legacy order storage.
	 *
	 * @return array rows of [order_id, product_id, unix time], ordered by order.
	 */
	private static function order_rows( int $since ): array {
		global $wpdb;
		$statuses = "'" . implode( "','", self::PAID_STATUSES ) . "'";
		$hpos     = class_exists( \Automattic\WooCommerce\Utilities\OrderUtil::class )
			&& \Automattic\WooCommerce\Utilities\OrderUtil::custom_orders_table_usage_is_enabled();
		$orders   = $hpos
			? "SELECT id, UNIX_TIMESTAMP(date_created_gmt) t FROM {$wpdb->prefix}wc_orders WHERE type = 'shop_order' AND status IN ($statuses) AND date_created_gmt > FROM_UNIXTIME($since)"
			: "SELECT ID AS id, UNIX_TIMESTAMP(post_date_gmt) t FROM {$wpdb->posts} WHERE post_type = 'shop_order' AND post_status IN ($statuses) AND post_date_gmt > FROM_UNIXTIME($since)";
		$rows     = $wpdb->get_results(
			"SELECT o.id, im.meta_value, o.t FROM ($orders) o
			 JOIN {$wpdb->prefix}woocommerce_order_items oi ON oi.order_id = o.id AND oi.order_item_type = 'line_item'
			 JOIN {$wpdb->prefix}woocommerce_order_itemmeta im ON im.order_item_id = oi.order_item_id AND im.meta_key = '_product_id'
			 ORDER BY o.id",
			ARRAY_N
		);
		return array_map(
			function ( $r ) {
				return array( (int) $r[0], (int) $r[1], (int) $r[2] );
			},
			(array) $rows
		);
	}

	/**
	 * Browsing sessions from the anonymous views table (last 60 days).
	 *
	 * @return int number of sessions.
	 */
	private static function collect_views( array &$pairs, array &$counts ): int {
		global $wpdb;
		$table    = Sophie_Rec_Store::views_table();
		$since    = time() - 60 * DAY_IN_SECONDS;
		$sessions = 0;
		$cur_sid  = null;
		$last_ts  = 0;
		$cur      = array();
		$flush    = function () use ( &$pairs, &$counts, &$cur, &$sessions ) {
			if ( count( $cur ) > 1 ) {
				self::add( $pairs, $counts, array_keys( $cur ), 1.0 );
				$sessions++;
			}
			$cur = array();
		};
		$offset   = 0;
		do {
			$rows = $wpdb->get_results( $wpdb->prepare( "SELECT sid, product_id, ts FROM $table WHERE ts > %d ORDER BY sid, ts DESC LIMIT %d OFFSET %d", $since, self::CHUNK, $offset ), ARRAY_N ); // phpcs:ignore WordPress.DB
			foreach ( (array) $rows as $r ) {
				$ts = (int) $r[2];
				if ( $r[0] !== $cur_sid || $last_ts - $ts > self::SESSION_GAP ) {
					$flush();
					$cur_sid = $r[0];
				}
				$last_ts              = $ts;
				$cur[ (int) $r[1] ] = true;
			}
			$offset += self::CHUNK;
		} while ( $rows && count( $rows ) === self::CHUNK && self::$pair_count < self::MAX_PAIRS && self::memory_ok() );
		$flush();
		return $sessions;
	}

	/** False once 70% of PHP's memory limit is used: stop learning, never crash the site. */
	private static function memory_ok(): bool {
		$limit = wp_convert_hr_to_bytes( (string) ini_get( 'memory_limit' ) );
		return $limit <= 0 || memory_get_usage() < 0.7 * $limit;
	}

	private static function add( array &$pairs, array &$counts, array $items, float $weight ): void {
		if ( self::$pair_count >= self::MAX_PAIRS || ! self::memory_ok() ) {
			return;
		}
		$n = min( count( $items ), 20 );
		self::$pair_count += (int) ( $n * ( $n - 1 ) / 2 );
		Sophie_Rec_Model::add_basket( $pairs, $counts, $items, $weight );
	}

	// --------------------------------------------------------------- write

	private static function write_sims( array $top, array $items ): int {
		global $wpdb;
		$values = array();
		foreach ( $top as $i => $row ) {
			$kept = 0;
			foreach ( $row as $j => $s ) {
				if ( $j === $i || ! isset( $items[ $j ] ) ) {
					continue; // only recommend products that are published & visible.
				}
				$values[] = $wpdb->prepare( '(%d,%d,%f)', $i, $j, $s );
				if ( ++$kept >= 30 ) {
					break;
				}
			}
		}
		self::swap_table( Sophie_Rec_Store::sim_table(), '(product_id, related_id, score)', $values );
		return count( $values );
	}

	/** Fills a copy of $table and atomically swaps it in. */
	private static function swap_table( string $table, string $columns, array $values ): void {
		global $wpdb;
		$new = $table . '_new';
		$old = $table . '_old';
		$wpdb->query( "DROP TABLE IF EXISTS $new, $old" ); // phpcs:ignore WordPress.DB
		$wpdb->query( "CREATE TABLE $new LIKE $table" ); // phpcs:ignore WordPress.DB
		foreach ( array_chunk( $values, 1000 ) as $chunk ) {
			$wpdb->query( "INSERT INTO $new $columns VALUES " . implode( ',', $chunk ) ); // phpcs:ignore WordPress.DB
		}
		$wpdb->query( "RENAME TABLE $table TO $old, $new TO $table" ); // phpcs:ignore WordPress.DB
		$wpdb->query( "DROP TABLE IF EXISTS $old" ); // phpcs:ignore WordPress.DB
	}

	private static function prune_views(): void {
		global $wpdb;
		$table  = Sophie_Rec_Store::views_table();
		$cutoff = time() - 90 * DAY_IN_SECONDS;
		do {
			$deleted = $wpdb->query( $wpdb->prepare( "DELETE FROM $table WHERE ts < %d LIMIT 10000", $cutoff ) ); // phpcs:ignore WordPress.DB
		} while ( $deleted >= 10000 );
	}
}
