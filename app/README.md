# Sophie's Online Shopping — App

用 Flutter 编写，一套代码同时支持 **Android**（已完成，可直接打包上架）和 **iOS**（后续在 Mac 上打包即可）。

直接对接现有的 **WooCommerce 网站**：商品、库存、价格、优惠券、运费、订单全部来自网站后台，App 里下的单会出现在 WooCommerce 订单列表中，无需维护第二套后台。

## 功能

| 模块 | 说明 |
|---|---|
| 首页 | 搜索框、分类快捷入口、"On sale" 特价横滑、热门商品无限滚动 |
| 分类 / 列表 | 所有分类和子分类，按热门 / 最新 / 价格排序 |
| 搜索 | 边输入边搜索，保存最近搜索记录 |
| 商品详情 | 多图轮播、折扣标签、尺码/颜色等规格选择、数量、加购 / 立即购买 |
| 购物车 | 修改数量、左滑删除、优惠券 |
| 结账 | 字段与网站结账页（`functions.php`）一致：姓名、电话、County、Area、地址、Email（选填）。County → Area 下拉数据直接从 `functions.php` 生成。选好县后自动计算运费，支付方式读取网站已启用的方式（货到付款、M-Pesa 等）|
| 我的 | 订单记录、心愿单、保存的收货信息、WhatsApp 客服、个性化广告开关 |
| 深度链接 | 网站商品链接 `https://你的域名/product/xxx/` 可以直接在 App 中打开；广告可用 `sophieshop://open/product/123` |

### 速度与体验
- Flutter AOT 原生编译，Android 单设备下载约 20 MB
- 首页和分类数据缓存在本地：二次打开**秒开**，后台静默刷新
- 图片按显示尺寸解码并缓存在磁盘，列表滚动流畅
- 广告 SDK 在后台初始化，**不拖慢启动速度**；任何 SDK 出错都不会影响购物
- 加购、改数量采用"先更新界面再同步服务器"，点击即时响应
- 再次结账时自动填充上次的收货信息

## 广告平台对接

App 内统一记录标准电商事件，并同时发送给各平台，用于广告转化优化和再营销受众：

| 事件 | Meta | Google (Firebase) | TikTok | X (经 AppsFlyer) |
|---|---|---|---|---|
| 浏览商品 | ViewContent | view_item | ViewContent | af_content_view |
| 搜索 | Search | search | Search | af_search |
| 加入购物车 | AddToCart | add_to_cart | AddToCart | af_add_to_cart |
| 加入心愿单 | AddToWishlist | add_to_wishlist | AddToWishlist | af_add_to_wishlist |
| 开始结账 | InitiatedCheckout | begin_checkout | Checkout | af_initiated_checkout |
| 购买 | Purchase（含金额 KES）| purchase | Purchase | af_purchase |

每个平台只在填入对应 ID 后才启用，没填的平台会自动跳过。

1. **Meta（Facebook / Instagram）**：在 developers.facebook.com 创建 App → 添加 Android 平台（包名、Key Hash）→ 把 App ID 和 Client Token 填到配置里。
2. **Google**：在 Firebase 控制台创建项目并添加 Android 应用 → 下载 `google-services.json` 放到 `android/app/` → 在 Google Ads 中关联 Firebase，把 `purchase` 导入为转化，即可投放"应用广告系列"。
3. **TikTok**：TikTok Ads Manager → Events Manager → 添加 App → 拿到 App ID 和 TikTok App ID 填入配置。
4. **X (Twitter)**：X 没有自己的 App 事件 SDK，App 广告归因必须通过 MMP（移动归因平台）。本项目接入了 **AppsFlyer**：注册后填入 Dev Key，在 AppsFlyer 中启用 "X Ads" 合作伙伴，事件就会同步给 X。同一套接入也能用于 Snapchat、Pinterest 等平台。AppsFlyer 超出免费额度后收费，如果不投 X 可以先不填。

隐私：「我的 → 个性化广告」开关可以一键停止向所有平台发送数据（符合肯尼亚《数据保护法》和 Google Play 政策）。

## 配置

```bash
cp config/app_config.example.json config/app_config.json   # 填入网站地址和各平台 ID
```

`app_config.json` 已加入 `.gitignore`，不会提交到 Git。Gradle 打包时也会读取这个文件（App 名称、Meta ID、深度链接域名），所以只需要维护这一个文件。

**不填 `STORE_URL` 时 App 以演示模式运行**，使用内置的示例商品，方便试用和截图。

### 网站端需要确认
1. WooCommerce 6.x 以上（Store API `/wp-json/wc/store/v1` 默认开启）。可以先在浏览器打开 `https://你的域名/wp-json/wc/store/v1/products` 检查是否能看到商品 JSON。
2. 如果用了安全插件或 Cloudflare，需要放行 `/wp-json/wc/store/` 路径。
3. App Links（网站链接直接打开 App）：上架后把 Play Console → 应用完整性 里的 SHA-256 证书指纹写进网站的 `/.well-known/assetlinks.json`。
4. 网站结账页把 Email 设成了选填。如果某个插件强制要求 Email，App 会直接显示网站返回的错误提示。

## 开发与打包

需要安装 Flutter 3.50 或以上版本，以及 Android SDK。

```bash
flutter pub get
flutter run --dart-define-from-file=config/app_config.json          # 真机调试
flutter test                                                         # 单元测试 + 完整下单流程测试
flutter build appbundle --dart-define-from-file=config/app_config.json   # 上架用 AAB
```

### 上架 Google Play
1. 生成签名密钥（务必备份，丢失后无法更新 App）：
   ```bash
   keytool -genkey -v -keystore ~/sophie-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. 新建 `android/key.properties`（不要提交到 Git）：
   ```
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=/绝对路径/sophie-upload.jks
   ```
3. **确认 `APPLICATION_ID`**（默认 `com.sophieshop.app`），上架后不能再修改。
4. `flutter build appbundle ...`，然后在 Play Console 上传 `build/app/outputs/bundle/release/app-release.aab`。
5. Play Console 需要准备：应用图标（`store_assets/play_store_icon_512.png`，目前是占位图标，建议换成正式 Logo 后运行 `python3 tool/gen_icons.py --force`）、宣传图 1024×500、至少 2 张手机截图、隐私政策网址；在「数据安全」中声明收集了**广告 ID、购买记录、App 互动数据、姓名/电话/地址**。
6. 每次发布前在 `pubspec.yaml` 中把 `version: 1.0.0+1` 的 `+1` 加 1。

### iOS（后续）
Dart 代码不用改。需要准备 Mac + Xcode 和 Apple 开发者账号（99 美元/年），并补充：`GoogleService-Info.plist`、Info.plist 中的 Facebook 配置和 `NSUserTrackingUsageDescription`（ATT 跟踪授权弹窗）、Associated Domains（深度链接），然后执行 `flutter build ipa`。

## 代码结构

```
lib/
  config.dart              构建时配置（--dart-define-from-file）
  data/store_api.dart      WooCommerce Store API 客户端（购物车 Cart-Token、缓存、错误处理）
  data/demo_store.dart     演示模式的离线商品
  data/regions.dart        County / Area（来自 functions.php）
  models/                  商品、购物车、金额、地址
  state/                   购物车、心愿单、个人资料
  tracking/                广告平台：meta / firebase / tiktok / appsflyer
  ui/                      主题（品牌色在 ui/theme.dart 的 `brand`）、页面、组件
tool/gen_ke_regions.py     从 ../functions.php 重新生成 assets/ke_regions.json
tool/gen_icons.py          生成启动图标
```

修改了网站 `functions.php` 中的地区列表后，执行 `python3 tool/gen_ke_regions.py ../functions.php assets/ke_regions.json` 同步到 App。
