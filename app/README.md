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

### 性能（已用 sophie.co.ke 实测）

App 和网站共用同一台服务器，所以优化分两部分：既要让 App 快，也要不给网站增加负担。

实测网站接口（未缓存时）：商品列表约 1.7 秒、商品详情约 1.3 秒、全部 736 个分类约 3.6 秒。数据量不是瓶颈（gzip 后只有 20 KB 左右），时间主要花在服务器的 PHP / WooCommerce 处理上。

**App 端**
- 列表只请求卡片需要的字段（`_fields`），数据量减少约 35%；详情页再加载完整信息
- 分类只加载 18 个一级分类（1.4 秒，原来要加载全部 736 个，3.6 秒），点进去再加载子分类
- 网站分类链接直接用 slug 查询商品，无需先下载全部分类
- 所有列表、分类、详情都保存到手机缓存目录：再次打开**直接显示**，后台静默更新；离线时也能浏览上次的内容
- 较大的 JSON 放到后台线程解析，滚动不卡顿
- 浏览商品的请求不带购物车令牌，所有顾客的请求完全相同，所以服务器和 Cloudflare 都能缓存
- 只浏览不加购的用户**不会在服务器上创建会话**（原来每次打开 App 都会请求一次购物车）
- 同一个请求同时发起多次时只发送一次；图片按显示尺寸解码，使用网站已有的 450×450 webp 缩略图

**服务器端（推荐安装，见下方"服务器端缓存"）**：商品和分类接口的响应时间可以从 1.3–1.8 秒降到缓存命中时的约 0.1–0.3 秒，网站本身也不会因为 App 流量变慢。

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

示例配置里已经填好了 `STORE_URL: https://sophie.co.ke`。**不填 `STORE_URL` 时 App 以演示模式运行**，使用内置的示例商品，方便试用和截图。

### 服务器端缓存（推荐）

`../wordpress/mu-plugins/sophie-app-cache.php` 是一个 WordPress "必用插件"（mu-plugin）：

1. 把它上传到服务器的 `wp-content/mu-plugins/` 目录（没有这个目录就新建一个），不需要手动启用。sophie.co.ke 的目录名可能不同：插件路径是 `/content/plugins/`，那么就放到 `/content/mu-plugins/`。
2. 验证：`curl -sI "https://sophie.co.ke/wp-json/wc/store/v1/products?per_page=1" | grep -i x-sophie-cache`，第一次显示 `MISS`，之后显示 `HIT`。

它只缓存**只读**的商品列表、商品详情和分类接口（每条最多保存 10 分钟）。购物车、结账、搜索和已登录用户的请求一律不缓存，网页也完全不受影响。商品、库存、价格、分类有任何变动，缓存都会立即失效。有 Redis 等对象缓存时使用对象缓存，没有就使用 `wp-content/cache/sophie-app/` 下的文件。

**可选：Cloudflare 边缘缓存**（网站已经在用 Cloudflare）。在 Cloudflare → Caching → Cache Rules 新建规则：URI Path 以 `/wp-json/wc/store/v1/products` 开头 → Eligible for cache，Edge TTL 选 "Use cache-control header if present, bypass cache if not"。插件会为可缓存的响应设置 5 分钟的 `s-maxage`，肯尼亚用户直接从 Cloudflare 内罗毕节点拿到数据，请求不再到达服务器。

### 网站端已确认 / 需要注意
1. ✅ Store API 可以正常访问，商品、分类、详情、加入/移出购物车都已用 `test_live/` 中的测试实测通过（测试**不会**下单）。
2. ✅ 当前唯一启用的支付方式是 M-Pesa（HS WooCommerce M-Pesa 插件），使用账单电话号码，没有额外字段。App 下单后会打开插件返回的支付页面。**请用一个小额商品真实下单一次**，确认 STK 推送或付款页面正常。
3. 如果用了安全插件（Wordfence 等）限制 REST API，需要放行 `/wp-json/wc/store/` 路径。
4. App Links（网站链接直接打开 App）：上架后把 Play Console → 应用完整性 里的 SHA-256 证书指纹写进网站的 `/.well-known/assetlinks.json`。
5. 网站的条款里已经写了"website and mobile application"，正好覆盖 App。

## 开发与打包

需要安装 Flutter 3.50 或以上版本，以及 Android SDK。

```bash
flutter pub get
flutter run --dart-define-from-file=config/app_config.json          # 真机调试
flutter test                                                         # 单元测试 + 完整下单流程测试（演示数据）
flutter test test_live                                               # 对 sophie.co.ke 的实测（不下单）
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
