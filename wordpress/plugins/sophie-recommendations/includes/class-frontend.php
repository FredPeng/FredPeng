<?php
/**
 * Shortcode, theme-styled product cards, tracking script, related products.
 *
 * Why the section loads with JavaScript: the home page is served from the
 * page cache / Cloudflare (the same HTML for everyone). The personal part is
 * fetched separately with the visitor's history in the URL, so that request
 * is cacheable too (same history -> same answer) and costs the server only a
 * few indexed queries when it is not cached.
 *
 * @package Sophie_Recommendations
 */

defined( 'ABSPATH' ) || exit;

final class Sophie_Rec_Frontend {

	public static function init(): void {
		add_shortcode( 'sophie_for_you', array( __CLASS__, 'shortcode' ) );
		add_action( 'wp_enqueue_scripts', array( __CLASS__, 'enqueue' ) );
		add_action( 'wp_footer', array( __CLASS__, 'footer_data' ), 5 );
		add_action( 'wp_ajax_sophie_rec_for_you', array( __CLASS__, 'ajax_for_you' ) );
		add_action( 'wp_ajax_nopriv_sophie_rec_for_you', array( __CLASS__, 'ajax_for_you' ) );
		if ( sophie_rec_settings()['related'] ) {
			add_filter( 'woocommerce_related_products', array( __CLASS__, 'related' ), 20, 3 );
		}
	}

	public static function enqueue(): void {
		wp_register_style( 'sophie-rec', SOPHIE_REC_URL . 'assets/for-you.css', array(), SOPHIE_REC_VERSION );
		wp_register_script( 'sophie-rec', SOPHIE_REC_URL . 'assets/for-you.js', array(), SOPHIE_REC_VERSION, array( 'in_footer' => true, 'strategy' => 'defer' ) );
		$s = sophie_rec_settings();
		wp_localize_script(
			'sophie-rec',
			'sophieRecConfig',
			array(
				'ajax'     => admin_url( 'admin-ajax.php' ),
				'track'    => $s['tracking'] ? rest_url( 'sophie-rec/v1/track' ) : '',
				'version'  => Sophie_Rec_Store::model_version(),
			)
		);
		// The small tracking part runs on every page (views, add to cart, orders).
		wp_enqueue_script( 'sophie-rec' );
	}

	/** Tells the script which product is being viewed / which were just bought. */
	public static function footer_data(): void {
		$data = array();
		if ( is_product() ) {
			$data['view'] = get_queried_object_id();
		}
		if ( function_exists( 'is_order_received_page' ) && is_order_received_page() ) {
			$order_id = absint( get_query_var( 'order-received' ) );
			$order    = $order_id ? wc_get_order( $order_id ) : null;
			$key      = isset( $_GET['key'] ) ? wc_clean( wp_unslash( $_GET['key'] ) ) : ''; // phpcs:ignore WordPress.Security.NonceVerification
			if ( $order && hash_equals( $order->get_order_key(), $key ) ) {
				$data['bought'] = array_values(
					array_map(
						function ( $item ) {
							return $item->get_product_id();
						},
						$order->get_items()
					)
				);
			}
		}
		if ( $data ) {
			printf( '<script>window.sophieRecPage=%s;</script>', wp_json_encode( $data ) );
		}
	}

	/**
	 * [sophie_for_you title="Products For You" limit="8" columns="4"]
	 */
	public static function shortcode( $atts ): string {
		$s    = sophie_rec_settings();
		$atts = shortcode_atts(
			array(
				'title'   => $s['title'],
				'limit'   => $s['limit'],
				'columns' => $s['columns'],
			),
			$atts,
			'sophie_for_you'
		);
		wp_enqueue_style( 'sophie-rec' );
		$limit   = max( 1, min( 24, (int) $atts['limit'] ) );
		$columns = max( 1, min( 6, (int) $atts['columns'] ) );
		ob_start();
		?>
		<section class="sophie-for-you woocommerce" data-limit="<?php echo esc_attr( $limit ); ?>" data-columns="<?php echo esc_attr( $columns ); ?>" style="--sfy-cols: <?php echo esc_attr( $columns ); ?>">
			<?php if ( '' !== trim( $atts['title'] ) ) : ?>
				<h2 class="sophie-for-you__title"><?php echo esc_html( $atts['title'] ); ?></h2>
			<?php endif; ?>
			<div class="sophie-for-you__grid" aria-busy="true">
				<?php for ( $i = 0; $i < $limit; $i++ ) : ?>
					<div class="sophie-for-you__skeleton"><span></span><i></i><i></i></div>
				<?php endfor; ?>
			</div>
		</section>
		<?php
		return (string) ob_get_clean();
	}

	/**
	 * admin-ajax endpoint: GET ?action=sophie_rec_for_you&h=1,2&p=3&n=8&c=4&s=SEED
	 * Rendered with the theme's own product card template (content-product.php),
	 * so cards look exactly like the rest of the shop.
	 */
	public static function ajax_for_you(): void {
		// phpcs:disable WordPress.Security.NonceVerification -- public, read-only, cacheable.
		$history   = self::ids( $_GET['h'] ?? '' );
		$purchased = self::ids( $_GET['p'] ?? '' );
		$limit     = max( 1, min( 24, absint( $_GET['n'] ?? 8 ) ) );
		$columns   = max( 1, min( 6, absint( $_GET['c'] ?? 4 ) ) );
		$seed      = substr( sanitize_key( wp_unslash( $_GET['s'] ?? '' ) ), 0, 20 );
		// phpcs:enable

		$ids  = array_keys( Sophie_Rec_Recommender::for_visitor( $history, $purchased, $limit, $seed . gmdate( 'Ymd' ) ) );
		$html = self::render_cards( $ids, $columns );

		// admin-ajax sends no-cache headers; this response only depends on the
		// URL, so let browsers and Cloudflare keep it for a while.
		header_remove( 'Cache-Control' );
		header_remove( 'Expires' );
		header_remove( 'Pragma' );
		header( 'Cache-Control: public, max-age=600, s-maxage=3600' );
		header( 'Content-Type: text/html; charset=' . get_option( 'blog_charset' ) );
		header( 'X-Robots-Tag: noindex' );
		echo $html; // phpcs:ignore WordPress.Security.EscapeOutput -- WooCommerce templates escape their output.
		exit; // not wp_die(): it would send no-cache headers again.
	}

	public static function render_cards( array $ids, int $columns ): string {
		if ( ! $ids ) {
			return '';
		}
		// admin-ajax is a front-end context for WooCommerce, but make sure the
		// loop template hooks are present in case something removed them.
		if ( ! has_action( 'woocommerce_shop_loop_item_title' ) && function_exists( 'WC' ) ) {
			include_once WC_ABSPATH . 'includes/wc-template-hooks.php';
		}
		global $post;
		$original = $post;
		ob_start();
		wc_setup_loop(
			array(
				'name'    => 'sophie_for_you',
				'columns' => $columns,
				'is_shortcode' => true,
			)
		);
		woocommerce_product_loop_start();
		foreach ( $ids as $id ) {
			$post = get_post( $id ); // phpcs:ignore WordPress.WP.GlobalVariablesOverride
			if ( ! $post ) {
				continue;
			}
			setup_postdata( $post );
			wc_get_template_part( 'content', 'product' );
		}
		woocommerce_product_loop_end();
		wc_reset_loop();
		$post = $original; // phpcs:ignore WordPress.WP.GlobalVariablesOverride
		wp_reset_postdata();
		return (string) ob_get_clean();
	}

	/** Better "Related products": bought/viewed together first, then the theme's own picks. */
	public static function related( $related, $product_id, $args ) {
		$limit   = max( 4, (int) ( $args['limit'] ?? 4 ) );
		$similar = Sophie_Rec_Recommender::similar( (int) $product_id, $limit );
		if ( ! $similar ) {
			return $related;
		}
		$excluded = array_map( 'absint', (array) ( $args['excluded_ids'] ?? array() ) );
		$merged   = array_values( array_diff( array_unique( array_merge( $similar, array_map( 'absint', (array) $related ) ) ), $excluded, array( (int) $product_id ) ) );
		// WooCommerce shuffles and then cuts this list to $limit: return exactly
		// $limit so the similar products are always the ones shown.
		return array_slice( $merged, 0, $limit );
	}

	private static function ids( $raw ): array {
		$raw = is_string( $raw ) ? $raw : '';
		return array_slice( array_values( array_filter( array_map( 'absint', explode( ',', $raw ) ) ) ), 0, 20 );
	}
}
