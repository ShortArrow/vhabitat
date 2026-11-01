# ADR-0001: サイトは Cloudflare Workers Builds で vhabitat.shortarrow.jp に公開する

- 状態: 採用

## 文脈

サイトは Hugo でビルドし、GitHub Actions から GitHub Pages に公開していた。持ち主のほかの静的サイト（mblint.shortarrow.jp など）は、shortarrow.jp の下で静的アセットを配る Cloudflare Workers で、それぞれのリポジトリから Workers Builds がビルドしている。Workers Builds は push されたブランチを CI を待たずに公開する。Cloudflare は GitHub の OIDC トークンを受け付けないので、GitHub Actions から公開するには、長命の Cloudflare の API トークンをリポジトリのシークレットに置くことになる。

## 決定

- サイトは、vhabitat.shortarrow.jp で `public/` を静的アセットとして配る Worker とする。Workers Builds をリポジトリにつなぎ、`main` を公開し、ほかのブランチは preview としてビルドする。
- ビルドコマンドは `wrangler.jsonc` の `build.command` に置き、`wrangler deploy` がビルドから公開までを行う。Hugo の版は Workers Builds の環境変数 `HUGO_VERSION` で指定する。
- GitHub Actions は Markdown のリンク検査だけを行う。
- `main` はリンク検査が通るプルリクエストでしか変えず、これをルールセットで強制する。

## 理由

- サイトが、持ち主のほかのサイトと同じドメインとアカウントに並ぶ。
- GitHub に Cloudflare の認証情報を置かない。
- ビルドコマンドがリポジトリにあるので、ダッシュボードの設定とリポジトリが食い違わない。
- Workers Builds はリンク検査を待たないので、公開される commit が検査済みであることは `main` の保護で保つ。

## 採らなかった案

- GitHub Pages に置き続ける：shortarrow.jp の下にあるほかのサイトとは別に、サイトを置く場所がもう一つ増える。
- リンク検査の後に GitHub Actions から Wrangler で公開する：長命の Cloudflare の API トークンをリポジトリのシークレットに置くことになる。

## 結果

- `main` へ直接 push することはやめる。
- ローカルで `wrangler dev` や `wrangler deploy` を使うには、`HUGO_VERSION` と同じ版の Hugo が PATH に要る。
