/// 赛道知识库页面（v1.5.2）：目录形式 + 左侧二级菜单。
///
/// 入口在左侧菜单“赛道知识库”。内容见 track_knowledge.dart
/// （9 分类 × 34 篇，面向赛道日新手；规则以当年规则与当日
/// 简报为准）。排版：列表页是分类目录（每分类标题 + 篇数徽标 +
/// 全部文章行，一目了然）；左上角目录钮打开左侧抽屉，抽屉里是
/// 同一份目录树（分类 → 文章），点任意文章直接跳转，当前文章
/// 高亮。文章页同样带抽屉，读完一篇可直接跳下一篇。
/// 深色底 #121212、卡片 #1E1E1E、DtAppBar，与 App 风格一致。

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_locale.dart';
import 'card_style.dart';
import 'track_knowledge.dart';
import 'track_knowledge_en.dart';

/// 知识库列表页：顶部说明卡 + 9 张分类目录卡 + 参考来源。
class TrackKnowledgePage extends StatelessWidget {
  const TrackKnowledgePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: Text(s.t('赛道知识库', 'Track guide')),
        leading: _DirectoryButton(),
      ),
      drawer: _KnowledgeDirectory(
        onSelect: (article) => _openArticle(context, article),
      ),
      body: ListView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 12, 16, 24)),
        children: [
          DriveTrackCard(
            child: Text(
              s.t(
                '面向赛道日新手的静态参考：旗语、规则、赛事架构、驾驶技术。点左上角目录可快速跳转到任意文章。规则以各赛事当年规则与当日安全简报为准；标“未核实”的内容请以官方资料为准。',
                'A static guide for a first track day: flags, rules, how a race is built, and driving. The directory at the top left jumps to any article. That year’s rules and that day’s briefing win. Anything marked unverified should be checked against the official source.',
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          for (final category in trackKnowledge) ...[
            _CategorySection(category: category),
            const SizedBox(height: 12),
          ],
          DriveTrackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t('参考来源', 'Sources'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                for (final source in trackKnowledgeSources)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '· ${knowledgeText(s.zh, source)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 左上角目录钮：打开左侧目录抽屉（需 Scaffold 下的 context）。
class _DirectoryButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu),
      tooltip: S.of(context).t('目录', 'Contents'),
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }
}

/// 关抽屉后打开文章页（列表页用 push）。
void _openArticle(BuildContext context, KnowledgeArticle article) {
  Navigator.of(context).pop();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TrackKnowledgeArticlePage(article: article),
    ),
  );
}

/// 分类目录卡：标题行（标题 + 副标题 + 篇数徽标）+ 全部文章行。
class _CategorySection extends StatelessWidget {
  final KnowledgeCategory category;
  const _CategorySection({required this.category});

  @override
  Widget build(BuildContext context) {
    final zh = S.of(context).zh;
    return DriveTrackCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    knowledgeText(zh, category.title),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    knowledgeText(zh, category.subtitle),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                zh
                    ? '${category.articles.length} 篇'
                    : '${category.articles.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),
        for (final article in category.articles)
          _ArticleRow(article: article),
      ]),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  final KnowledgeArticle article;
  const _ArticleRow({required this.article});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrackKnowledgeArticlePage(article: article),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          const Icon(Icons.article_outlined, size: 18, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              knowledgeText(S.of(context).zh, article.title),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
        ]),
      ),
    );
  }
}

/// 左侧目录抽屉：与列表页同一份目录树（分类 → 文章），点文章直接跳。
/// [current] 为当前正在读的文章（文章页传入），在抽屉里高亮。
class _KnowledgeDirectory extends StatelessWidget {
  final KnowledgeArticle? current;
  final ValueChanged<KnowledgeArticle> onSelect;
  const _KnowledgeDirectory({this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final total =
        trackKnowledge.fold<int>(0, (n, c) => n + c.articles.length);
    return Drawer(
      backgroundColor: const Color(0xFF0B0E13),
      width: 300,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t('赛道知识库', 'Track guide'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.t(
                        '目录 · ${trackKnowledge.length} 个分类 · $total 篇文章',
                        'Contents · ${trackKnowledge.length} sections · $total articles',
                      ),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: s.t('关闭目录', 'Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: ListView(children: [
              for (final category in trackKnowledge) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        knowledgeText(s.zh, category.title),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      s.zh
                          ? '${category.articles.length} 篇'
                          : '${category.articles.length}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ]),
                ),
                for (final article in category.articles)
                  _DirectoryRow(
                    article: article,
                    selected: identical(article, current),
                    onTap: () => onSelect(article),
                  ),
              ],
              const SizedBox(height: 16),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  final KnowledgeArticle article;
  final bool selected;
  final VoidCallback onTap;
  const _DirectoryRow({
    required this.article,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? Colors.white12 : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
        child: Row(children: [
          Icon(
            Icons.circle,
            size: 6,
            color: selected ? Colors.white : Colors.white38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              knowledgeText(S.of(context).zh, article.title),
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 文章详情页：导读 + 要点列表（要点名加粗）+ 底部提醒；同样带目录抽屉。
class TrackKnowledgeArticlePage extends StatelessWidget {
  final KnowledgeArticle article;
  const TrackKnowledgeArticlePage({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    final zh = S.of(context).zh;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: Text(knowledgeText(zh, article.title)),
        leading: _DirectoryButton(),
      ),
      drawer: _KnowledgeDirectory(
        current: article,
        onSelect: (next) {
          if (identical(next, article)) {
            Navigator.of(context).pop();
            return;
          }
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TrackKnowledgeArticlePage(article: next),
            ),
          );
        },
      ),
      body: ListView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 12, 16, 24)),
        children: [
          DriveTrackCard(
            child: Text(
              knowledgeText(zh, article.intro),
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          DriveTrackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < article.bullets.length; i++) ...[
                  _BulletText(text: knowledgeText(zh, article.bullets[i])),
                  if (i != article.bullets.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          DriveTrackCard(
            child: Text(
              S.of(context).t(
                '规则以各赛事当年规则与当日安全简报为准；标“未核实”的内容请以官方资料为准。',
                'That year’s rules and that day’s briefing win. Anything marked unverified should be checked against the official source.',
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 要点行：圆点 + 正文；“要点名：说明”格式的，把冒号前的要点名加粗。
class _BulletText extends StatelessWidget {
  final String text;
  const _BulletText({required this.text});

  @override
  Widget build(BuildContext context) {
    var idx = text.indexOf('：');
    var colon = '：';
    if (idx < 0) {
      idx = text.indexOf(':');
      colon = ':';
    }
    final hasLead = idx > 0 &&
        idx <= 48 &&
        !text.substring(0, idx).contains('。') &&
        !text.substring(0, idx).contains('；');
    final lead = hasLead ? text.substring(0, idx) : null;
    final body = hasLead ? text.substring(idx + colon.length) : text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 6, color: Colors.white54),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5),
              children: [
                if (lead != null)
                  TextSpan(
                    text: '$lead$colon',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
