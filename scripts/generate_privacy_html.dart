/// 隐私政策 HTML 生成脚本
///
/// 用法：
///   dart run scripts/generate_privacy_html.dart
///
/// 输出：docs/privacy_policy.html
///
/// 修改隐私政策内容后，运行此脚本重新生成 HTML，然后将
/// docs/privacy_policy.html 部署到服务器即可。
library;

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:easyfile/core/content/privacy_policy_content.dart';

void main() {
  final output = _buildHtml();

  final outFile = File('docs/privacy_policy.html');
  outFile.writeAsStringSync(output, encoding: utf8);

  print('✅ 已生成 ${outFile.path}  (版本 ${PrivacyPolicyContent.version})');
}

// ---------------------------------------------------------------------------
// HTML builder
// ---------------------------------------------------------------------------

String _buildHtml() {
  final buf = StringBuffer();

  buf.writeln('<!doctype html>');
  buf.writeln('<html lang="zh-CN">');
  buf.writeln();
  buf.writeln('<head>');
  buf.writeln('   <meta charset="utf-8" />');
  buf.writeln('   <meta name="viewport" content="width=device-width,initial-scale=1" />');
  buf.writeln('   <title>关于${PrivacyPolicyContent.appName}与隐私的声明</title>');
  buf.writeln('   <style>');
  buf.writeln(_css);
  buf.writeln('   </style>');
  buf.writeln('</head>');
  buf.writeln();
  buf.writeln('<body>');
  buf.writeln('   <header>');
  buf.writeln('      <h1>关于${PrivacyPolicyContent.appName}与隐私的声明</h1>');
  buf.writeln('      <div class="meta">');
  buf.writeln('         <div>更新日期：${PrivacyPolicyContent.lastUpdated}</div>');
  buf.writeln('         <div>生效日期：${PrivacyPolicyContent.effectiveDate}</div>');
  buf.writeln('      </div>');
  buf.writeln('   </header>');
  buf.writeln('   <main>');

  for (final section in PrivacyPolicyContent.sections) {
    if (section.isCard) {
      _writeCard(buf, section);
    } else {
      _writeSection(buf, section);
    }
  }

  buf.writeln();
  buf.writeln('      <footer class="footer">');
  buf.writeln('         <p><strong>生效日期：${PrivacyPolicyContent.effectiveDate}</strong></p>');
  buf.writeln('      </footer>');
  buf.writeln('   </main>');
  buf.writeln('</body>');
  buf.writeln();
  buf.writeln('</html>');

  return buf.toString();
}

void _writeSection(StringBuffer buf, PrivacySection section) {
  buf.writeln();
  buf.writeln('      <section>');
  buf.writeln('         <h2>${_esc(section.title)}</h2>');

  if (section.content != null && section.content!.isNotEmpty) {
    buf.writeln('         <p>${_linkify(_esc(section.content!))}</p>');
  }

  if (section.items.isNotEmpty) {
    buf.writeln('         <ul>');
    for (final item in section.items) {
      buf.writeln('            <li>${_linkify(_esc(item))}</li>');
    }
    buf.writeln('         </ul>');
  }

  if (section.footer != null && section.footer!.isNotEmpty) {
    buf.writeln('         <p><em>${_linkify(_esc(section.footer!))}</em></p>');
  }

  buf.writeln('      </section>');
}

void _writeCard(StringBuffer buf, PrivacySection section) {
  buf.writeln();
  buf.writeln('      <div class="card" role="note">');
  buf.writeln('         <h2>${_esc(section.title)}</h2>');

  if (section.content != null && section.content!.isNotEmpty) {
    buf.writeln('         <p>${_linkify(_esc(section.content!))}</p>');
  }

  if (section.items.isNotEmpty) {
    // Card items shown with checkmark prefix (matching original HTML style)
    buf.write('         <p>');
    buf.write(section.items.map((item) => '✓ ${_linkify(_esc(item))}').join('<br>\n            '));
    buf.writeln('</p>');
  }

  if (section.footer != null && section.footer!.isNotEmpty) {
    buf.writeln('         <p>${_linkify(_esc(section.footer!))}</p>');
  }

  buf.writeln('      </div>');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// HTML-escape special characters.
String _esc(String text) =>
    text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Turn bare URLs and email addresses into clickable links (after HTML-escape).
String _linkify(String html) {
  // mailto links
  html = html.replaceAllMapped(
    RegExp(r'\b([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})\b'),
    (m) => '<a href="mailto:${m[1]}">${m[1]}</a>',
  );

  // https:// links
  html = html.replaceAllMapped(
    RegExp(r'https?://[^\s<&"]+'),
    (m) {
      // strip any trailing HTML entity that leaked in (e.g. &amp; already
      // escaped by _esc, but the URL should end before the entity)
      final url = m[0]!;
      return '<a href="$url" target="_blank" rel="noopener">$url</a>';
    },
  );

  return html;
}

// ---------------------------------------------------------------------------
// Page CSS
// ---------------------------------------------------------------------------

const _css = r'''
      body {
         font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
         color: #111;
         background: #fff;
         line-height: 1.7;
         padding: 24px;
      }

      header {
         max-width: 900px;
         margin: 0 auto 24px
      }

      main {
         max-width: 900px;
         margin: 0 auto
      }

      h1 {
         font-size: 24px;
         margin: 8px 0
      }

      h2 {
         font-size: 18px;
         margin: 18px 0 8px
      }

      h3 {
         font-size: 16px;
         margin: 12px 0 6px
      }

      p {
         margin: 8px 0
      }

      ul {
         margin: 8px 0 16px;
         padding-left: 1.2em
      }

      .meta {
         color: #666;
         font-size: 13px;
         margin-top: 8px
      }

      .meta div {
         margin: 4px 0
      }

      .card {
         background: #f5f7fb;
         border-radius: 8px;
         padding: 16px;
         margin-top: 24px;
         border: 1px solid #eef2f8
      }

      .footer {
         margin-top: 48px;
         padding-top: 24px;
         border-top: 1px solid #eee;
         text-align: center;
         color: #999;
         font-size: 14px
      }

      a {
         color: #0066cc;
         text-decoration: none
      }

      a:hover {
         text-decoration: underline
      }

      em {
         color: #666;
         font-style: italic
      }''';
