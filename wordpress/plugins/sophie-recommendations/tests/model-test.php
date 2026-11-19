<?php
/**
 * Unit tests for the algorithm. Run: php tests/model-test.php
 */
define( 'ABSPATH', __DIR__ );
require __DIR__ . '/../includes/class-model.php';

$fail = 0;
function check( $cond, $msg ) {
	global $fail;
	echo ( $cond ? 'PASS ' : 'FAIL ' ) . $msg . "\n";
	if ( ! $cond ) {
		$fail = 1;
	}
}

// --- similarity -------------------------------------------------------------
// Phone (1) is often bought with case (2) and charger (3); dress (10) with heels (11).
// Bestseller (99) is in many baskets with everything.
$pairs  = array();
$counts = array();
for ( $k = 0; $k < 20; $k++ ) {
	Sophie_Rec_Model::add_basket( $pairs, $counts, array( 1, 2, 99 ) );
}
for ( $k = 0; $k < 15; $k++ ) {
	Sophie_Rec_Model::add_basket( $pairs, $counts, array( 1, 3 ) );
}
for ( $k = 0; $k < 20; $k++ ) {
	Sophie_Rec_Model::add_basket( $pairs, $counts, array( 10, 11, 99 ) );
}
for ( $k = 0; $k < 60; $k++ ) {
	Sophie_Rec_Model::add_basket( $pairs, $counts, array( 99, 1000 + $k ) );
}
Sophie_Rec_Model::add_basket( $pairs, $counts, array( 1, 50 ) ); // one-off pair
Sophie_Rec_Model::add_basket( $pairs, $counts, range( 200, 260 ) ); // huge basket, capped at 20

check( ! isset( $counts[250] ), 'huge baskets are capped' );
$sims = Sophie_Rec_Model::similarities( $pairs, $counts );
check( isset( $sims[1][2], $sims[2][1] ) && abs( $sims[1][2] - $sims[2][1] ) < 1e-9, 'similarity is symmetric' );
check( $sims[1][2] > $sims[1][99], 'case is more similar to phone than the bestseller is (popularity penalty)' );
check( $sims[1][2] > $sims[1][50], 'a 20x pair beats a one-off pair (shrinkage)' );
check( ! isset( $sims[1][10] ), 'never-co-bought products are not similar' );

$top = Sophie_Rec_Model::blend_top_k( array( array( $sims, 1.0 ), array( array( 1 => array( 3 => 5.0 ) ), 0.4 ) ), 2 );
check( count( $top[1] ) === 2 && array_key_first( $top[1] ) === 3, 'blend adds view similarity and keeps top K sorted' );

// --- ranking ------------------------------------------------------------------
$items = array(
	1  => array( 'leaf' => 100, 'top' => 1 ),
	2  => array( 'leaf' => 101, 'top' => 1 ),
	3  => array( 'leaf' => 101, 'top' => 1 ),
	4  => array( 'leaf' => 101, 'top' => 1 ),
	5  => array( 'leaf' => 101, 'top' => 1 ),
	6  => array( 'leaf' => 101, 'top' => 1 ),
	10 => array( 'leaf' => 200, 'top' => 2 ),
	11 => array( 'leaf' => 201, 'top' => 2 ),
	12 => array( 'leaf' => 201, 'top' => 2 ),
	99 => array( 'leaf' => 300, 'top' => 3 ),
	77 => array( 'leaf' => 400, 'top' => 4 ),
);
$base = array(
	'sims'      => array(
		1  => array( 2 => 0.9, 3 => 0.8, 4 => 0.7, 5 => 0.6, 6 => 0.5, 99 => 0.1 ),
		10 => array( 11 => 0.9, 12 => 0.6 ),
	),
	'items'     => $items,
	'cat_trend' => array(
		101 => array( 2 => 5, 3 => 4, 6 => 1 ),
		201 => array( 12 => 9, 11 => 3 ),
	),
	'trending'  => array( 99 => 50, 77 => 40, 12 => 10 ),
	'limit'     => 4,
	'seed'      => 'visitor-a:2026-11-19',
);

$r = Sophie_Rec_Model::rank( $base + array( 'history' => array( 1 ) ) );
check( array_key_first( $r ) === 2, 'viewer of the phone gets the case first' );
check( ! isset( $r[1] ), 'already viewed product is not recommended' );
check( count( $r ) === 4, 'returns the requested number' );
$cats = array_count_values( array_map( fn( $id ) => $items[ $id ]['leaf'], array_keys( $r ) ) );
check( max( $cats ) <= 3, 'diversity: not everything from one category' );

$r2 = Sophie_Rec_Model::rank( $base + array( 'history' => array( 10, 1 ) ) );
check( array_key_first( $r2 ) === 11, 'most recent view (dress) dominates' );
check( isset( $r2[2] ), 'older interest (phone) still represented' );

$r3 = Sophie_Rec_Model::rank( $base + array( 'history' => array( 1 ), 'purchased' => array( 2 ) ) );
check( ! isset( $r3[2] ), 'purchased products are not recommended again' );

$r4 = Sophie_Rec_Model::rank( $base + array( 'history' => array() ) );
check( array_key_first( $r4 ) === 99 && isset( $r4[77] ), 'new visitor: trending products' );

$r5 = Sophie_Rec_Model::rank( $base + array( 'history' => array( 1 ), 'exclude' => array( 2, 3 ) ) );
check( ! isset( $r5[2] ) && ! isset( $r5[3] ), 'excluded (e.g. out of stock) never returned' );

$a = Sophie_Rec_Model::rank( $base + array( 'history' => array( 1 ) ) );
check( array_keys( $a ) === array_keys( $r ), 'stable for the same visitor and day' );

$r6 = Sophie_Rec_Model::rank( $base + array( 'history' => array( 12345 ) ) );
check( array_key_first( $r6 ) === 99, 'unknown product in history falls back to trending' );

exit( $fail );
