# ADR-0006: ページは、ビルドで出したスクリプトと Google Analytics だけを実行させ、図版は描くことだけに限る

- 状態: 採用

## 文脈

サイトの応答には、Cloudflare の既定のヘッダーしか付いていなかった。ページが実行するスクリプトは、テーマが出す 5 つのインラインスクリプト（配色と場所の復元、speculation rules、ページ送り、Google Analytics の設定）、テーマの `/js/` にある 2 つのファイル、`www.googletagmanager.com` の gtag.js である。
本番では、これに Cloudflare が配信のときに差し込む 2 つのスクリプトが加わる。Bot Fight Mode のボット検出（JavaScript Detections）のインラインスクリプトと、Cloudflare Web Analytics のビーコン `static.cloudflareinsights.com/beacon.min.js` である。どちらもビルドの出力にはない。テーマは要素の `style` 属性にも値を書く。

Workers の静的アセットは、アセットのディレクトリにある `_headers` の規則を応答に付ける。ファイル自体は配らない。

### 守るものと、攻撃者が握れる経路

サイトにはログインもフォームもない。攻撃者のスクリプトが `vhabitat.shortarrow.jp` として訪問者のブラウザで動けば、偽サイトへの誘導やページの書き換えができる。同じ `shortarrow.jp` の他のサイトがドメイン全体に効く `HttpOnly` でない Cookie を使っていれば、それも読める。

ページの中身を決めるのは、リポジトリの Markdown、テーマ、各項目の図版である。

- Markdown の生の HTML は、Hugo の既定どおり出力されない。
- テーマの JS は、URL や入力から HTML を書かない。
- テーマは、図版 `plate.svg` の中身を生の HTML としてページに埋め込む（`safeHTML`）。図版は `/<セクション>/<項目>/plate.svg` としても単独で配られる。ADR-0005 で図版の「目撃情報求む」を掲げているので、図版は外部の人から寄せられうる。SVG には `<script>` や `onload` 属性を書け、長い図の中ではレビューで見落としやすい。

攻撃者が現実に握れる経路は、この図版である。テーマの `/js/` のファイルと Google Tag Manager が乗っ取られる経路もあるが、どちらもこのリポジトリの外で決まり、ここで決める対策では止められない。

## 決定

- `static/_headers` で、全ページに Content-Security-Policy を付ける。
  - `script-src` は、`'self'`、インラインスクリプトごとの `'sha256-…'`、`https://*.googletagmanager.com`、`https://static.cloudflareinsights.com` とする。`'unsafe-inline'` は使わない。
  - `connect-src` には、Google の CSP の手引き（developers.google.com/tag-platform/security/guides/csp）が広告機能なしの Google Analytics に挙げる `https://*.google-analytics.com`、`https://*.google.com`、`https://*.googletagmanager.com` を入れる。`*.google.com` は、gtag.js が `*.google-analytics.com` に送れなかったときの送り先である。
  - `script-src` の `https://static.cloudflareinsights.com` と `connect-src` の `https://cloudflareinsights.com` は、Cloudflare の CSP の文書（developers.cloudflare.com/fundamentals/reference/policies-compliances/content-security-policies/）が Web Analytics に挙げる送り先である。プロキシしたサイトでは、ビーコンは同じドメインの `/cdn-cgi/rum` に送るので、`'self'` で足りる。`cloudflareinsights.com` は、文書のとおりに足しておく。
  - `img-src` には、同じ手引きに従い `https://*.google-analytics.com` と `https://*.googletagmanager.com` を入れる。
  - `style-src` は `'self' 'unsafe-inline'` とする。
  - `object-src 'none'`、`base-uri 'self'`、`form-action 'self'`、`frame-ancestors 'none'` を付ける。
- ハッシュは、Workers Builds と同じ `hugo --minify` の出力から取る。`tests/headers.sh` が同じビルドをして、ページが実行するスクリプトのうちポリシーが許さないものを、そのまま `script-src` に足せる形で示して失敗する。
- 図版は `tests/plate_check.py` で検査し、CI で描くこと以外ができる図版を落とす。
  - 検査するのは、`content/` の `plate.svg` と、ビルドしたページにテーマが実際に埋め込んだ図版の両方である。テーマは `.Resources.GetMatch "plate.svg"` で図版を選び、この照合は大文字小文字を区別せず、front matter の `name` で別のファイルにも当たるためである。
  - `content/` に置けるファイルは、`.md` と `plate.svg` だけとする。ページバンドルのほかのファイルはそのまま配られ、そこから読み込むスクリプトは CSP の `'self'` で動いてしまうためである。
  - 図版は BOM と NUL のない UTF-8 に限る。テーマは図版のバイト列を UTF-8 のページにそのまま埋め込むので、ほかの文字コードとして読むと、検査の見ない `<script>` を書けてしまう。
  - XML として解析し、DOCTYPE、コメント、処理命令、CDATA を拒む。ページは HTML として解析されるので、これらは XML と終わる位置が変わる。
  - 要素と属性は許可した一覧のものだけを、SVG の名前空間で受け付ける。`fill` と `stroke` は `none` か `currentColor` に限る（ADR-0005）。文字は `title` と `desc` の中だけに許す。

## 理由

- CSP と図版の検査を両方とる。片方では、もう片方の抜けを埋められない。
  - 図版の検査は、悪い図版を本番に届く前に止め、本番には何の代償もない。ただ、文字列や許可リストによる検査は、`<use href>`、`<foreignObject>`、エンティティ、大文字小文字や改行の揺れのような、思いつかなかった形で抜けうる。
  - CSP は、検査を抜けた図版のスクリプトを、ブラウザの側で確実に止める二重目の守りになる。
- インラインスクリプトをハッシュで許せば、ページに差し込まれたスクリプトは動かない。`'unsafe-inline'` ではこれが守れない。
- インラインスクリプトの中身は全ページで同じ 5 つなので、ハッシュは 5 つで足りる。
- `style` 属性の値はページごと、印章ごとに違い、ハッシュで並べきれない。スタイルの差し込みはスクリプトほどの害がないので、`'unsafe-inline'` を許す。
- Cloudflare Web Analytics のビーコンは許す。
  - ビーコンを配る `static.cloudflareinsights.com` も、送り先の `cloudflareinsights.com` も、サイトを配信している Cloudflare のものである。Cloudflare はもともと全ページのバイト列を配っており、書き換えることもできる。許しても、信頼する相手は増えない。
  - 許さないと、Cloudflare Web Analytics でページの読み込みの速さが測れない。
- CSP の代償は小さい。
  - 本番では、Cloudflare が Bot Fight Mode のボット検出（JavaScript Detections）のインラインスクリプトを差し込む。中身はリクエストごとに変わるのでハッシュで許せず、CSP で止まる。Cloudflare の文書では、この判定の結果を遮断に使うには Enterprise Bot Management の契約と WAF の規則が要り、判定が否でもそれだけでは遮断されない。Bot Fight Mode の判定がこの結果をどれだけ使うかは、文書にない（未規定）。
  - 残る代償は、テーマを上げるたびにハッシュを書き換える手間で、`tests/headers.sh` がそれを知らせる。

## 採らなかった案

- 図版の検査だけにする：検査が抜けたときに、止めるものがなくなる。
- CSP だけにする：悪い図版がリポジトリに入り、配られた図版を直接開いたときの扱いまで CSP に任せることになる。図版を受け付ける時点で止められるのに止めない。
- `script-src` に `'unsafe-inline'` を許す：テーマの更新で手入れが要らない代わりに、CSP の主な効き目を失う。
- nonce を使う：静的なサイトでは応答ごとに値を変えられない。応答ごとに変えるには配信の Worker にコードを足すことになり、ADR-0001 の静的アセットだけの構成から外れる。
- テーマがハッシュ付きのポリシーを出す：テーマの変更を待つことになる。テーマがそれを出せるようになれば、この決定を見直す。

## 結果

- テーマか Hugo の版を上げてインラインスクリプトの中身が変わると、`tests/headers.sh` が失敗する。示されたハッシュで `static/_headers` の `script-src` を書き換え、古いハッシュを消す。
- Google Analytics の送信先が上の 3 つから外れると、計測が止まる。Google Ads を Google Analytics につなぐときは、手引きの Ads の送信先も足す。
- 本番の各ページで、Cloudflare のボット検出のスクリプトが CSP に止められ、ブラウザのコンソールにエラーが 1 件出る。
- Cloudflare が差し込むスクリプトは、ビルドの出力からは検査できない。`tests/headers.sh` は、Web Analytics の 2 つの送り先がポリシーにあることだけを確かめる。Cloudflare の機能を新しく有効にするときは、本番のページでポリシーの違反が出ないかを確かめ、要るなら送り先を足す。
- ページが測るもの（Google Analytics と Cloudflare Web Analytics）は、プライバシーポリシーに書く。`tests/run.sh` が、その名前がポリシーのページにあることを確かめる。
- 項目に図版以外の画像やファイルを添えるときは、`tests/plates.sh` の許すファイルの決まりと、この決定を見直す。
- 図版に新しい要素や属性を使うときは、`tests/plate_check.py` の一覧に足す。足す前に、それがスクリプトの実行や外部の読み込みにつながらないかを確かめる。
