<?php
/**
 * Request-time recommendations (a handful of indexed queries, no heavy work).
 *
 * @package Sophie_Recommendations
 */

defined( 'ABSPATH' ) || exit;

final class Sophie_Rec_Recommender {

	/**
	 * @param int[]  $history   recently viewed / carted product ids, most recent first.
	 * @param int[]  $purchased bought product ids.
	 * @param int    $limit     how many to return.
	 * @param string $seed      varies results slightly per visitor per day.
	 * @return array [id => ['score' => float, 'reason' => string]]
	 */
	public static function for_visitor( array $history, array $purchased, int $limit, string $seed = '' ): array {
		$history   = array_slice( array_values( array_unique( array_filter( array_map( 'absint', $history ) ) ) ), 0, 20 );
		$purchased = array_slice( array_values( array_unique( array_filter( array_map( 'absint', $purchased ) ) ) ), 0, 20 );
		$limit     = max( 1, min( 24, $limit ) );

		$cache_key = 'fy_' . md5( implode( ',', $history ) . '|' . implode( ',', $purchased ) . "|$limit|$seed|" . Sophie_Rec_Store::model_version() );
		$cached    = wp_cache_get( $cache_key, 'sophie_rec' );
		if ( is_array( $cached ) ) {
			return $cached;
		}

		$signals  = array_merge( $history, $purchased );
		$sims     = Sophie_Rec_Store::sims_for( $signals );
		$trending = Sophie_Rec_Store::trending( 60 );
		$sig_info = Sophie_Rec_Store::items_for( $signals );

		// Popular products from the categories this visitor looks at.
		$cat_trend = array();
		$aff       = array();
		foreach ( $signals as $k => $id ) {
			if ( isset( $sig_info[ $id ] ) ) {
				$w = pow( 0.85, $k );
				if ( $sig_info[ $id ]['leaf'] ) {
					$aff[ 'l' . $sig_info[ $id ]['leaf'] ] = ( $aff[ 'l' . $sig_info[ $id ]['leaf'] ] ?? 0 ) + $w;
				}
				if ( $sig_info[ $id ]['top'] ) {
					$aff[ 't' . $sig_info[ $id ]['top'] ] = ( $aff[ 't' . $sig_info[ $id ]['top'] ] ?? 0 ) + 0.3 * $w;
				}
			}
		}
		arsort( $aff );
		foreach ( array_slice( array_keys( $aff ), 0, 5 ) as $key ) {
			$cat               = (int) substr( $key, 1 );
			$cat_trend[ $cat ] = ( $cat_trend[ $cat ] ?? array() ) + Sophie_Rec_Store::category_trending( $cat, 't' === $key[0] );
		}

		// Candidate pool: only products that are currently in stock & visible.
		$candidates = array_keys( $trending );
		foreach ( $sims as $row ) {
			$candidates = array_merge( $candidates, array_keys( $row ) );
		}
		foreach ( $cat_trend as $row ) {
			$candidates = array_merge( $candidates, array_keys( $row ) );
		}
		$available = Sophie_Rec_Store::items_for( $candidates, true );

		foreach ( $sims as $sid => $row ) {
			$sims[ $sid ] = array_intersect_key( $row, $available );
		}
		foreach ( $cat_trend as $cat => $row ) {
			$cat_trend[ $cat ] = array_intersect_key( $row, $available );
		}

		$ranked = Sophie_Rec_Model::rank(
			array(
				'history'   => $history,
				'purchased' => $purchased,
				'sims'      => $sims,
				'items'     => $available + $sig_info,
				'cat_trend' => $cat_trend,
				'trending'  => array_intersect_key( $trending, $available ),
				'limit'     => $limit + 4, // spare in case a product changed since the last build.
				'seed'      => $seed,
			)
		);

		// Final live check (stock / visibility can change between builds).
		$out = array();
		foreach ( $ranked as $id => $info ) {
			$product = wc_get_product( $id );
			if ( $product && $product->is_visible() && $product->is_in_stock() && $product->is_purchasable() ) {
				$out[ $id ] = $info;
				if ( count( $out ) >= $limit ) {
					break;
				}
			}
		}
		wp_cache_set( $cache_key, $out, 'sophie_rec', HOUR_IN_SECONDS );
		return $out;
	}

	/** Similar products for one product (used for "Related products"). */
	public static function similar( int $product_id, int $limit ): array {
		$sims = Sophie_Rec_Store::sims_for( array( $product_id ) )[ $product_id ] ?? array();
		if ( ! $sims ) {
			return array();
		}
		$available = Sophie_Rec_Store::items_for( array_keys( $sims ), true );
		$sims      = array_intersect_key( $sims, $available );
		if ( ! $sims ) {
			return array();
		}
		// Only clear relationships: drop pairs much weaker than the best one
		// (one-off coincidences). WooCommerce's own picks fill the remaining slots.
		$cutoff = 0.2 * max( $sims );
		$sims   = array_filter(
			$sims,
			function ( $s ) use ( $cutoff ) {
				return $s >= $cutoff;
			}
		);
		arsort( $sims );
		return array_slice( array_keys( $sims ), 0, $limit );
	}
}
