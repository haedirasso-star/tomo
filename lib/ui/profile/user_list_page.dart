part of '../../main.dart';

/// المتابِعون / المتابَعون (تبويبان)
class UserListPage extends StatefulWidget {
  final String uid, title;
  final bool followers;
  const UserListPage({super.key, required this.uid, required this.followers, required this.title});
  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: widget.followers ? 1 : 0,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            bottom: TabBar(indicatorColor: E.ink, labelColor: E.ink, unselectedLabelColor: E.ink3,
                tabs: [Tab(text: 'أتابعه'), Tab(text: 'المتابِعون')]),
          ),
          body: TabBarView(children: [_List(uid: widget.uid, followers: false), _List(uid: widget.uid, followers: true)]),
        ),
      );
}

class _List extends StatefulWidget {
  final String uid;
  final bool followers;
  const _List({required this.uid, required this.followers});
  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> with AutomaticKeepAliveClientMixin {
  List<Profile>? _l;
  Set<String> _f = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.people(widget.uid, followers: widget.followers);
      _f = await Api.followingIds(l.map((p) => p.id).toList());
      _l = l;
    } catch (_) {
      _l = [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = _l;
    if (l == null) return const Loading();
    if (l.isEmpty) return const EmptyState(icon: Icons.people_outline_rounded, title: 'لا أحد بعد');
    return ListView(children: [for (final p in l) PersonTile(p, following: _f.contains(p.id))]);
  }
}
