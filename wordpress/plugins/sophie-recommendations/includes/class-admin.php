<?php
/**
 * WooCommerce → Recommendations: settings, model status, rebuild, preview.
 *
 * @package Sophie_Recommendations
 */

defined( 'ABSPATH' ) || exit;

final class Sophie_Rec_Admin {

	/**
	 * Creates the "See all" page ([sophie_for_you_all]) once. If it is deleted
	 * or changed, the setting below points to whichever page you choose.
	 */
	public static function ensure_page(): void {
		$id = (int) get_option( 'sophie_rec_page_id' );
		if ( $id && get_post( $id ) ) {
			return;
		}
		$id = wp_insert_post(
			array(
				'post_type'    => 'page',
				'post_status'  => 'publish',
				'post_title'   => 'Products For You',
				'post_name'    => 'for-you',
				'post_content' => "<!-- wp:shortcode -->\n[sophie_for_you_all]\n<!-- /wp:shortcode -->",
			)
		);
		if ( $id && ! is_wp_error( $id ) ) {
			update_option( 'sophie_rec_page_id', (int) $id, false );
		}
	}

	public static function init(): void {
		add_action( 'admin_init', array( __CLASS__, 'ensure_page' ) );
		add_action( 'admin_menu', array( __CLASS__, 'menu' ), 60 );
		add_action( 'admin_init', array( __CLASS__, 'register' ) );
		add_action( 'admin_post_sophie_rec_rebuild', array( __CLASS__, 'rebuild' ) );
		add_filter( 'plugin_action_links_' . plugin_basename( SOPHIE_REC_FILE ), array( __CLASS__, 'links' ) );
	}

	public static function links( array $links ): array {
		array_unshift( $links, '<a href="' . esc_url( admin_url( 'admin.php?page=sophie-rec' ) ) . '">' . esc_html__( 'Settings', 'sophie-rec' ) . '</a>' );
		return $links;
	}

	public static function menu(): void {
		add_submenu_page( 'woocommerce', __( 'Recommendations', 'sophie-rec' ), __( 'Recommendations', 'sophie-rec' ), 'manage_woocommerce', 'sophie-rec', array( __CLASS__, 'page' ) );
	}

	public static function register(): void {
		register_setting( 'sophie_rec', 'sophie_rec_page_id', array( 'type' => 'integer', 'sanitize_callback' => 'absint' ) );
		register_setting(
			'sophie_rec',
			'sophie_rec_settings',
			array(
				'type'              => 'array',
				'sanitize_callback' => function ( $in ) {
					$in = (array) $in;
					return array(
						'title'        => sanitize_text_field( $in['title'] ?? '' ),
						'limit'        => max( 1, min( 24, absint( $in['limit'] ?? 8 ) ) ),
						'columns'      => max( 1, min( 6, absint( $in['columns'] ?? 4 ) ) ),
						'tracking'     => empty( $in['tracking'] ) ? 0 : 1,
						'related'      => empty( $in['related'] ) ? 0 : 1,
						'exclude_cats' => implode( ',', array_filter( array_map( 'absint', explode( ',', (string) ( $in['exclude_cats'] ?? '' ) ) ) ) ),
					);
				},
			)
		);
	}

	public static function rebuild(): void {
		if ( ! current_user_can( 'manage_woocommerce' ) ) {
			wp_die( esc_html__( 'Not allowed.', 'sophie-rec' ) );
		}
		check_admin_referer( 'sophie_rec_rebuild' );
		Sophie_Rec_Builder::build();
		wp_safe_redirect( admin_url( 'admin.php?page=sophie-rec&rebuilt=1' ) );
		exit;
	}

	public static function page(): void {
		$s     = sophie_rec_settings();
		$stats = (array) get_option( 'sophie_rec_stats', array() );
		global $wpdb;
		$views = (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . Sophie_Rec_Store::views_table() ); // phpcs:ignore WordPress.DB
		// phpcs:disable WordPress.Security.NonceVerification -- read-only preview.
		$preview_ids = isset( $_GET['preview'] ) ? sanitize_text_field( wp_unslash( $_GET['preview'] ) ) : '';
		// phpcs:enable
		?>
		<div class="wrap">
			<h1><?php esc_html_e( 'Products For You – Recommendations', 'sophie-rec' ); ?></h1>
			<?php if ( isset( $_GET['rebuilt'] ) ) : // phpcs:ignore ?>
				<div class="notice notice-success"><p><?php esc_html_e( 'Model rebuilt.', 'sophie-rec' ); ?></p></div>
			<?php endif; ?>

			<h2><?php esc_html_e( 'How to show it', 'sophie-rec' ); ?></h2>
			<p><?php esc_html_e( 'Home page: add a "Shortcode" element (Elementor) with:', 'sophie-rec' ); ?> <code>[sophie_for_you]</code> &nbsp; <?php esc_html_e( 'or', 'sophie-rec' ); ?> &nbsp; <code>[sophie_for_you title="Products For You" limit="4" columns="4"]</code></p>
			<p><?php esc_html_e( 'To use your own Elementor heading instead, add the shortcode with title="" and link your heading to the "See all" page:', 'sophie-rec' ); ?> <code>[sophie_for_you title=""]</code></p>
			<p><?php esc_html_e( '"See all" page (all recommendations, best first):', 'sophie-rec' ); ?>
				<?php $all = Sophie_Rec_Frontend::all_url(); ?>
				<?php if ( $all ) : ?>
					<a href="<?php echo esc_url( $all ); ?>" target="_blank"><?php echo esc_html( $all ); ?></a>
					· <a href="<?php echo esc_url( get_edit_post_link( (int) get_option( 'sophie_rec_page_id' ) ) ); ?>"><?php esc_html_e( 'edit page', 'sophie-rec' ); ?></a>
				<?php else : ?>
					<?php esc_html_e( 'not found – create a page containing [sophie_for_you_all] and set its ID below.', 'sophie-rec' ); ?>
				<?php endif; ?>
			</p>

			<h2><?php esc_html_e( 'Model status', 'sophie-rec' ); ?></h2>
			<table class="widefat striped" style="max-width:720px">
				<tbody>
				<tr><td><?php esc_html_e( 'Last build', 'sophie-rec' ); ?></td><td><?php echo ! empty( $stats['built_at'] ) ? esc_html( wp_date( 'Y-m-d H:i', $stats['built_at'] ) . ' (' . $stats['seconds'] . ' s, ' . $stats['memory_mb'] . ' MB)' ) : '—'; ?></td></tr>
				<tr><td><?php esc_html_e( 'Recommendable products', 'sophie-rec' ); ?></td><td><?php echo esc_html( $stats['products'] ?? '—' ); ?></td></tr>
				<tr><td><?php esc_html_e( 'Products with learned "similar" items', 'sophie-rec' ); ?></td><td><?php echo esc_html( isset( $stats['with_similar'] ) ? $stats['with_similar'] . ' (' . $stats['similar_rows'] . ' pairs)' : '—' ); ?></td></tr>
				<tr><td><?php esc_html_e( 'Purchase baskets used (365 days)', 'sophie-rec' ); ?></td><td><?php echo esc_html( isset( $stats['baskets'] ) ? $stats['baskets'] . ' · ' . $stats['source'] : '—' ); ?></td></tr>
				<tr><td><?php esc_html_e( 'Browsing sessions used (60 days)', 'sophie-rec' ); ?></td><td><?php echo esc_html( $stats['sessions'] ?? '—' ); ?></td></tr>
				<tr><td><?php esc_html_e( 'Anonymous views stored (max 90 days)', 'sophie-rec' ); ?></td><td><?php echo esc_html( number_format_i18n( $views ) ); ?></td></tr>
				<tr><td><?php esc_html_e( 'Schedule', 'sophie-rec' ); ?></td><td><?php esc_html_e( 'Similar products: nightly 03:00 · Trending: hourly', 'sophie-rec' ); ?></td></tr>
				</tbody>
			</table>
			<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" style="margin-top:12px">
				<input type="hidden" name="action" value="sophie_rec_rebuild">
				<?php wp_nonce_field( 'sophie_rec_rebuild' ); ?>
				<?php submit_button( __( 'Rebuild now', 'sophie-rec' ), 'secondary', 'submit', false ); ?>
			</form>

			<h2><?php esc_html_e( 'Preview', 'sophie-rec' ); ?></h2>
			<form method="get">
				<input type="hidden" name="page" value="sophie-rec">
				<p><label><?php esc_html_e( 'Pretend a visitor viewed these product IDs (most recent first, empty = new visitor):', 'sophie-rec' ); ?><br>
				<input type="text" name="preview" value="<?php echo esc_attr( $preview_ids ); ?>" class="regular-text" placeholder="123, 456"></label>
				<?php submit_button( __( 'Show recommendations', 'sophie-rec' ), 'secondary', '', false ); ?></p>
			</form>
			<?php
			if ( isset( $_GET['preview'] ) ) : // phpcs:ignore
				$history = array_filter( array_map( 'absint', explode( ',', $preview_ids ) ) );
				$recs    = Sophie_Rec_Recommender::for_visitor( $history, array(), (int) $s['limit'], 'preview' );
				?>
				<table class="widefat striped" style="max-width:720px">
					<thead><tr><th><?php esc_html_e( 'Product', 'sophie-rec' ); ?></th><th><?php esc_html_e( 'Why', 'sophie-rec' ); ?></th><th><?php esc_html_e( 'Score', 'sophie-rec' ); ?></th></tr></thead>
					<tbody>
					<?php foreach ( $history as $hid ) : ?>
						<tr style="opacity:.6"><td><?php echo esc_html( '↳ ' . __( 'viewed:', 'sophie-rec' ) . ' #' . $hid . ' ' . get_the_title( $hid ) ); ?></td><td></td><td></td></tr>
					<?php endforeach; ?>
					<?php foreach ( $recs as $id => $info ) : ?>
						<tr>
							<td><a href="<?php echo esc_url( get_permalink( $id ) ); ?>" target="_blank">#<?php echo esc_html( $id . ' ' . get_the_title( $id ) ); ?></a></td>
							<td><?php echo esc_html( array( 'similar' => __( 'Bought/viewed together', 'sophie-rec' ), 'category' => __( 'Popular in a category they like', 'sophie-rec' ), 'trending' => __( 'Trending', 'sophie-rec' ) )[ $info['reason'] ] ?? $info['reason'] ); ?></td>
							<td><?php echo esc_html( $info['score'] ); ?></td>
						</tr>
					<?php endforeach; ?>
					</tbody>
				</table>
			<?php endif; ?>

			<h2><?php esc_html_e( 'Settings', 'sophie-rec' ); ?></h2>
			<form method="post" action="options.php">
				<?php settings_fields( 'sophie_rec' ); ?>
				<table class="form-table" role="presentation">
					<tr><th><?php esc_html_e( 'Section title', 'sophie-rec' ); ?></th><td><input name="sophie_rec_settings[title]" value="<?php echo esc_attr( $s['title'] ); ?>" class="regular-text"></td></tr>
					<tr><th><?php esc_html_e( '"See all" page ID', 'sophie-rec' ); ?></th><td><input type="number" min="0" name="sophie_rec_page_id" value="<?php echo esc_attr( (int) get_option( 'sophie_rec_page_id' ) ); ?>"></td></tr>
					<tr><th><?php esc_html_e( 'Number of products (home page)', 'sophie-rec' ); ?></th><td><input type="number" min="1" max="24" name="sophie_rec_settings[limit]" value="<?php echo esc_attr( $s['limit'] ); ?>"></td></tr>
					<tr><th><?php esc_html_e( 'Columns (desktop)', 'sophie-rec' ); ?></th><td><input type="number" min="1" max="6" name="sophie_rec_settings[columns]" value="<?php echo esc_attr( $s['columns'] ); ?>"></td></tr>
					<tr><th><?php esc_html_e( 'Learn from browsing', 'sophie-rec' ); ?></th><td><label><input type="checkbox" name="sophie_rec_settings[tracking]" value="1" <?php checked( $s['tracking'] ); ?>> <?php esc_html_e( 'Record anonymous "viewed together" data (random session number only, no personal data). Recommended: purchases alone are sparse.', 'sophie-rec' ); ?></label></td></tr>
					<tr><th><?php esc_html_e( 'Related products', 'sophie-rec' ); ?></th><td><label><input type="checkbox" name="sophie_rec_settings[related]" value="1" <?php checked( $s['related'] ); ?>> <?php esc_html_e( 'Also use learned "bought/viewed together" items for the Related products on product pages.', 'sophie-rec' ); ?></label></td></tr>
					<tr><th><?php esc_html_e( 'Never recommend categories', 'sophie-rec' ); ?></th><td><input name="sophie_rec_settings[exclude_cats]" value="<?php echo esc_attr( $s['exclude_cats'] ); ?>" class="regular-text" placeholder="12, 34"><p class="description"><?php esc_html_e( 'Category IDs (sub-categories included). Applied at the next hourly update.', 'sophie-rec' ); ?></p></td></tr>
				</table>
				<?php submit_button(); ?>
			</form>
		</div>
		<?php
	}
}
