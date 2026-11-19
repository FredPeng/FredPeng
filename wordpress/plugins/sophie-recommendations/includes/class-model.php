<?php
/**
 * The recommendation algorithm (pure PHP, no WordPress calls, unit-tested).
 *
 * Offline (nightly): item-to-item collaborative filtering.
 *   - "Bought together": products bought by the same customer (last 365 days).
 *   - "Viewed together": products viewed in the same browsing session (last 60 days).
 *   Similarity = cosine of co-occurrence with shrinkage, so a pair seen once is
 *   trusted less than a pair seen 20 times, and best-sellers do not become
 *   "similar" to everything.
 *
 * Online (per visitor): score candidates from the visitor's recent views,
 * add-to-carts and purchases (more recent = more weight), blend with
 * category affinity and trending products, then re-rank for diversity so the
 * section is not 8 near-identical items.
 *
 * @package Sophie_Recommendations
 */

defined( 'ABSPATH' ) || exit;

final class Sophie_Rec_Model {

	/**
	 * Adds one basket (a customer's purchases or a session's views) to the
	 * co-occurrence counts.
	 *
	 * Large baskets are capped and down-weighted (1 / log2(1 + n)): a customer
	 * who bought 40 unrelated things says little about any single pair.
	 *
	 * @param array $pairs  [i][j] => weight, with i < j (half matrix saves memory).
	 * @param array $counts [i] => weight.
	 * @param int[] $items  Product ids, most relevant (e.g. most recent) first.
	 * @param float $weight Basket weight (e.g. time decay).
	 * @param int   $cap    Max items per basket.
	 */
	public static function add_basket( array &$pairs, array &$counts, array $items, float $weight = 1.0, int $cap = 20 ): void {
		$items = array_slice( array_values( array_unique( array_map( 'intval', $items ) ) ), 0, $cap );
		$n     = count( $items );
		if ( 0 === $n || $weight <= 0 ) {
			return;
		}
		foreach ( $items as $i ) {
			$counts[ $i ] = ( $counts[ $i ] ?? 0.0 ) + $weight;
		}
		if ( $n < 2 ) {
			return;
		}
		$w = $weight / log( 1 + $n, 2 );
		for ( $a = 0; $a < $n; $a++ ) {
			for ( $b = $a + 1; $b < $n; $b++ ) {
				$i = min( $items[ $a ], $items[ $b ] );
				$j = max( $items[ $a ], $items[ $b ] );
				$pairs[ $i ][ $j ] = ( $pairs[ $i ][ $j ] ?? 0.0 ) + $w;
			}
		}
	}

	/**
	 * Turns co-occurrence counts into similarity scores.
	 *
	 * sim(i,j) = c / sqrt(n_i * n_j) * c / (c + shrink)
	 *
	 * @return array [i] => [j => score, ...] (both directions), unsorted.
	 */
	public static function similarities( array $pairs, array $counts, float $shrink = 2.0, float $min_score = 0.001 ): array {
		$sims = array();
		foreach ( $pairs as $i => $row ) {
			foreach ( $row as $j => $c ) {
				$den = sqrt( ( $counts[ $i ] ?? 0 ) * ( $counts[ $j ] ?? 0 ) );
				if ( $den <= 0 ) {
					continue;
				}
				$s = ( $c / $den ) * ( $c / ( $c + $shrink ) );
				if ( $s < $min_score ) {
					continue;
				}
				$sims[ $i ][ $j ] = $s;
				$sims[ $j ][ $i ] = $s;
			}
		}
		return $sims;
	}

	/**
	 * Blends several similarity sources (e.g. purchases weight 1.0, views 0.4)
	 * and keeps the top K neighbours per product, best first.
	 *
	 * @param array $sources list of [ sims, weight ].
	 */
	public static function blend_top_k( array $sources, int $k = 30 ): array {
		$out = array();
		foreach ( $sources as $source ) {
			list( $sims, $weight ) = $source;
			foreach ( $sims as $i => $row ) {
				foreach ( $row as $j => $s ) {
					$out[ $i ][ $j ] = ( $out[ $i ][ $j ] ?? 0.0 ) + $weight * $s;
				}
			}
		}
		foreach ( $out as $i => $row ) {
			arsort( $row );
			$out[ $i ] = array_slice( $row, 0, $k, true );
		}
		return $out;
	}

	/**
	 * Ranks products for one visitor.
	 *
	 * @param array $in {
	 *   history:    int[]  viewed / added-to-cart ids, most recent first.
	 *   purchased:  int[]  bought ids (weaker signal, never recommended again).
	 *   sims:       [signal id => [candidate id => score]].
	 *   items:      [id => ['leaf' => int, 'top' => int]] for signals & candidates.
	 *   cat_trend:  [category id => [id => trend score]].
	 *   trending:   [id => trend score] global best sellers right now.
	 *   exclude:    int[] never return these.
	 *   limit:      int.
	 *   seed:       string, e.g. visitor + date: small daily variety.
	 * }
	 * @return array [id => ['score' => float, 'reason' => string]] best first.
	 */
	public static function rank( array $in ): array {
		$history   = array_values( array_unique( array_map( 'intval', $in['history'] ?? array() ) ) );
		$purchased = array_values( array_unique( array_map( 'intval', $in['purchased'] ?? array() ) ) );
		$sims      = $in['sims'] ?? array();
		$items     = $in['items'] ?? array();
		$cat_trend = $in['cat_trend'] ?? array();
		$trending  = $in['trending'] ?? array();
		$limit     = max( 1, (int) ( $in['limit'] ?? 8 ) );
		$seed      = (string) ( $in['seed'] ?? '' );
		$exclude   = array_flip( array_map( 'intval', array_merge( $in['exclude'] ?? array(), $history, $purchased ) ) );

		// 1. Signal weights: recency decay for views, purchases count less
		//    (people rarely buy the same kind of thing twice in a row).
		$signals = array();
		foreach ( $history as $k => $id ) {
			$signals[ $id ] = ( $signals[ $id ] ?? 0 ) + pow( 0.85, $k );
		}
		foreach ( $purchased as $k => $id ) {
			$signals[ $id ] = ( $signals[ $id ] ?? 0 ) + 0.5 * pow( 0.9, $k );
		}

		// 2. Collaborative filtering score. Each signal's neighbours are scaled
		//    to its own best match, so one product with very strong pairs
		//    (e.g. a phone and its case) cannot drown out a more recent interest.
		$cf = array();
		foreach ( $signals as $sid => $w ) {
			$row = $sims[ $sid ] ?? array();
			$max = $row ? max( $row ) : 0;
			if ( $max <= 0 ) {
				continue;
			}
			foreach ( $row as $cid => $s ) {
				$cf[ $cid ] = ( $cf[ $cid ] ?? 0.0 ) + $w * $s / $max;
			}
		}

		// 3. Category affinity -> popular products in the visitor's categories.
		$aff = array();
		foreach ( $signals as $sid => $w ) {
			if ( ! empty( $items[ $sid ]['leaf'] ) ) {
				$aff[ $items[ $sid ]['leaf'] ] = ( $aff[ $items[ $sid ]['leaf'] ] ?? 0 ) + $w;
			}
			if ( ! empty( $items[ $sid ]['top'] ) ) {
				$aff[ $items[ $sid ]['top'] ] = ( $aff[ $items[ $sid ]['top'] ] ?? 0 ) + 0.3 * $w;
			}
		}
		$aff_total = array_sum( $aff );
		$content   = array();
		foreach ( $aff as $cat => $a ) {
			$list = $cat_trend[ $cat ] ?? array();
			$max  = $list ? max( $list ) : 0;
			if ( $max <= 0 ) {
				continue;
			}
			foreach ( $list as $cid => $t ) {
				$content[ $cid ] = ( $content[ $cid ] ?? 0.0 ) + ( $a / $aff_total ) * ( $t / $max );
			}
		}

		// 4. Blend (each part normalised to 0..1).
		$cf      = self::normalise( $cf );
		$content = self::normalise( $content );
		$trend   = self::normalise( $trending );
		$personal = ! empty( $signals );
		$w_cf     = 1.0;
		$w_cont   = 0.35;
		$w_trend  = $personal ? 0.1 : 1.0;

		$scores = array();
		$reason = array();
		foreach ( array_keys( $cf + $content + $trend ) as $cid ) {
			if ( isset( $exclude[ $cid ] ) ) {
				continue;
			}
			$parts = array(
				'similar'  => $w_cf * ( $cf[ $cid ] ?? 0 ),
				'category' => $w_cont * ( $content[ $cid ] ?? 0 ),
				'trending' => $w_trend * ( $trend[ $cid ] ?? 0 ),
			);
			$s = array_sum( $parts );
			if ( $s <= 0 ) {
				continue;
			}
			// Up to +-4% deterministic jitter: a little daily variety, stable within a day.
			$s *= 1 + 0.08 * ( self::hash01( $seed . ':' . $cid ) - 0.5 );
			$scores[ $cid ] = $s;
			$reason[ $cid ] = array_search( max( $parts ), $parts, true );
		}
		arsort( $scores );

		// 5. Diversity re-rank: each extra item from the same category is
		//    penalised, so the section shows a varied mix.
		$picked    = array();
		$cat_count = array();
		$pool      = array_slice( $scores, 0, $limit * 6, true );
		while ( count( $picked ) < $limit && $pool ) {
			$best    = null;
			$best_sc = -1;
			foreach ( $pool as $cid => $s ) {
				$cat = $items[ $cid ]['leaf'] ?? 0;
				$adj = $s * pow( 0.6, $cat ? ( $cat_count[ $cat ] ?? 0 ) : 0 );
				if ( $adj > $best_sc ) {
					$best_sc = $adj;
					$best    = $cid;
				}
			}
			$cat = $items[ $best ]['leaf'] ?? 0;
			if ( $cat ) {
				$cat_count[ $cat ] = ( $cat_count[ $cat ] ?? 0 ) + 1;
			}
			$picked[ $best ] = array(
				'score'  => round( $pool[ $best ], 5 ),
				'reason' => $reason[ $best ],
			);
			unset( $pool[ $best ] );
		}
		return $picked;
	}

	private static function normalise( array $v ): array {
		$max = $v ? max( $v ) : 0;
		if ( $max <= 0 ) {
			return array();
		}
		foreach ( $v as $k => $x ) {
			$v[ $k ] = $x / $max;
		}
		return $v;
	}

	private static function hash01( string $s ): float {
		return ( crc32( $s ) % 10000 ) / 10000;
	}
}
