# ADR-0006: ページは、ビルドで出したスクリプトと Google Analytics だけを実行させる

- 状態: 採用

## 文脈

サイトの応答には、Cloudflare の既定のヘッダーしか付いていなかった。ページが実行するスクリプトは、テーマが出す 5 つのインラインスクリプト（配色と場所の復元、speculation rules、ページ送り、Google Analytics の設定）、テーマの `/js/` にある 2 つのファイル、`www.googletagmanager.com` の gtag.js である。テーマは要素の `style` 属性にも値を書く。

Workers の静的アセットは、アセットのディレクトリにある `_headers` の規則を応答に付ける。ファイル自体は配らない。

## 決定

- `static/_headers` で、全ページに Content-Security-Policy を付ける。
  - `script-src` は、`'self'`、インラインスクリプトごとの `'sha256-…'`、`https://*.googletagmanager.com` とする。`'unsafe-inline'` は使わない。
  - `connect-src` には、Google の CSP の手引き（developers.google.com/tag-platform/security/guides/csp）が広告機能なしの Google Analytics に挙げる `https://*.google-analytics.com`、`https://*.google.com`、`https://*.googletagmanager.com` を入れる。`*.google.com` は、gtag.js が `*.google-analytics.com` に送れなかったときの送り先である。
  - `img-src` には、同じ手引きに従い `https://*.google-analytics.com` と `https://*.googletagmanager.com` を入れる。
  - `style-src` は `'self' 'unsafe-inline'` とする。
  - `object-src 'none'`、`base-uri 'self'`、`form-action 'self'`、`frame-ancestors 'none'` を付ける。
- ハッシュは、Workers Builds と同じ `hugo --minify` の出力から取る。`tests/headers.sh` が同じビルドをして、ページが実行するスクリプトのうちポリシーが許さないものを、そのまま `script-src` に足せる形で示して失敗する。

## 理由

- インラインスクリプトをハッシュで許せば、ページに差し込まれたスクリプトは動かない。`'unsafe-inline'` ではこれが守れない。
- インラインスクリプトの中身は全ページで同じ 5 つなので、ハッシュは 5 つで足りる。
- `style` 属性の値はページごと、印章ごとに違い、ハッシュで並べきれない。スタイルの差し込みはスクリプトほどの害がないので、`'unsafe-inline'` を許す。

## 採らなかった案

- `script-src` に `'unsafe-inline'` を許す：テーマの更新で手入れが要らない代わりに、CSP の主な効き目を失う。
- nonce を使う：静的なサイトでは応答ごとに値を変えられない。
- テーマがハッシュ付きのポリシーを出す：テーマの変更を待つことになる。テーマがそれを出せるようになれば、この決定を見直す。

## 結果

- テーマか Hugo の版を上げてインラインスクリプトの中身が変わると、`tests/headers.sh` が失敗する。示されたハッシュで `static/_headers` の `script-src` を書き換え、古いハッシュを消す。
- Google Analytics の送信先が上の 3 つから外れると、計測が止まる。Google Ads を Google Analytics につなぐときは、手引きの Ads の送信先も足す。
