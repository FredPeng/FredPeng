<?php
/**
 * REST API:
 *   GET  /wp-json/sophie-rec/v1/for-you?h=12,34&p=56&n=8   ids for the mobile app
 *   GET  /wp-json/sophie-rec/v1/similar/123?n=8
 *   POST /wp-json/sophie-rec/v1/track   {"sid":123456,"items":[12,34]}  (batched by the browser)
 *
 * @package Sophie_Recommendations
 */

defined( 'ABSPATH' ) || exit;

final class Sophie_Rec_Rest {

	public static function init(): void {
		add_action( 'rest_api_init', array( __CLASS__, 'routes' ) );
	}

	public static function routes(): void {
		register_rest_route(
			'sophie-rec/v1',
			'/for-you',
			array(
				'methods'             => 'GET',
				'permission_callback' => '__return_true',
				'callback'            => array( __CLASS__, 'for_you' ),
				'args'                => array(
					'h' => array( 'type' => 'string', 'default' => '' ),
					'p' => array( 'type' => 'string', 'default' => '' ),
					'n' => array( 'type' => 'integer', 'default' => 8, 'minimum' => 1, 'maximum' => 48 ),
					'o' => array( 'type' => 'integer', 'default' => 0, 'minimum' => 0, 'maximum' => 96 ),
					's' => array( 'type' => 'string', 'default' => '' ),
				),
			)
		);
		register_rest_route(
			'sophie-rec/v1',
			'/similar/(?P<id>\d+)',
			array(
				'methods'             => 'GET',
				'permission_callback' => '__return_true',
				'callback'            => array( __CLASS__, 'similar' ),
				'args'                => array(
					'n' => array( 'type' => 'integer', 'default' => 8, 'minimum' => 1, 'maximum' => 24 ),
				),
			)
		);
		register_rest_route(
			'sophie-rec/v1',
			'/track',
			array(
				'methods'             => 'POST',
				'permission_callback' => '__return_true',
				'callback'            => array( __CLASS__, 'track' ),
			)
		);
	}

	private static function ids( string $raw ): array {
		return array_slice( array_values( array_filter( array_map( 'absint', explode( ',', $raw ) ) ) ), 0, 20 );
	}

	private static function cacheable( $data ): WP_REST_Response {
		$res = new WP_REST_Response( $data );
		$res->header( 'Cache-Control', 'public, max-age=600, s-maxage=3600' );
		return $res;
	}

	public static function for_you( WP_REST_Request $req ): WP_REST_Response {
		$h    = self::ids( (string) $req['h'] );
		$p    = self::ids( (string) $req['p'] );
		$seed = substr( sanitize_key( (string) $req['s'] ), 0, 20 ) . gmdate( 'Ymd' );
		$recs = Sophie_Rec_Recommender::for_visitor( $h, $p, (int) $req['n'], $seed, (int) $req['o'] );
		$out = array();
		foreach ( $recs as $id => $info ) {
			$out[] = array(
				'id'     => $id,
				'reason' => $info['reason'],
			);
		}
		return self::cacheable(
			array(
				'products' => $out,
				'total'    => Sophie_Rec_Recommender::count_for_visitor( $h, $p, $seed ),
				'version'  => Sophie_Rec_Store::model_version(),
			)
		);
	}

	public static function similar( WP_REST_Request $req ): WP_REST_Response {
		return self::cacheable( array( 'products' => Sophie_Rec_Recommender::similar( (int) $req['id'], (int) $req['n'] ) ) );
	}

	public static function track( WP_REST_Request $req ): WP_REST_Response {
		if ( ! sophie_rec_settings()['tracking'] || self::is_bot() ) {
			return new WP_REST_Response( null, 204 );
		}
		// sendBeacon posts text/plain (no CORS preflight), so parse the body ourselves.
		$body = json_decode( (string) $req->get_body(), true );
		if ( ! is_array( $body ) ) {
			return new WP_REST_Response( null, 204 );
		}
		$sid   = absint( $body['sid'] ?? 0 ) % 4294967295;
		$items = is_array( $body['items'] ?? null ) ? $body['items'] : array();
		Sophie_Rec_Store::insert_views( $sid, $items );
		$res = new WP_REST_Response( null, 204 );
		$res->header( 'Cache-Control', 'no-store' );
		return $res;
	}

	private static function is_bot(): bool {
		$ua = isset( $_SERVER['HTTP_USER_AGENT'] ) ? strtolower( (string) $_SERVER['HTTP_USER_AGENT'] ) : ''; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput
		return '' === $ua || (bool) preg_match( '/bot|crawl|spider|slurp|preview|headless|lighthouse|facebookexternalhit|curl|wget|python/', $ua );
	}
}
