import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String apiUrl = 'https://roman-vip.ir/app-api.php';

void main() => runApp(const RomanVipApp());

class RomanVipApp extends StatelessWidget {
  const RomanVipApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'رمان VIP',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff7546a8)),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        home: const HomePage(),
      );
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  Future<dynamic> post(String action, [Map<String, String> data = const {}]) async {
    final uri = Uri.parse(apiUrl);
    if (uri.scheme != 'https') throw ApiException('ارتباط امن HTTPS در دسترس نیست.');
    final response = await http
        .post(uri,
            headers: {'Accept': 'application/json'},
            body: {'action': action, ...data})
        .timeout(const Duration(seconds: 25)); // http encodes a Map as form data.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('خطای سرور (${response.statusCode}).');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException('پاسخ سرور JSON معتبر نیست.');
    }
    if (decoded is Map && (decoded['success'] == false || decoded['status'] == 'error')) {
      throw ApiException(_messageFrom(decoded) ?? 'درخواست ناموفق بود.');
    }
    return decoded;
  }

  Future<List<Novel>> getNovels() async {
    final payload = await post('get_novels');
    dynamic rows = payload;
    if (payload is Map) {
      rows = payload['novels'] ?? payload['posts'] ?? payload['data'] ?? payload['items'];
      if (rows is Map) rows = rows['novels'] ?? rows['posts'] ?? rows['items'];
    }
    if (rows is! List) throw ApiException('ساختار فهرست رمان‌ها در پاسخ API شناخته نشد.');
    return rows.whereType<Map>().map((e) => Novel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<String> authenticate(String action, String username, String password,
      {String? email}) async {
    final fields = <String, String>{'username': username, 'password': password};
    if (email != null && email.trim().isNotEmpty) fields['email'] = email.trim();
    final result = await post(action, fields);
    if (result is Map) {
      final message = _messageFrom(result);
      if (result['success'] == false || result['status'] == 'error') {
        throw ApiException(message ?? 'ورود/ثبت‌نام ناموفق بود.');
      }
      return message ?? (action == 'login' ? 'ورود موفق بود.' : 'ثبت‌نام انجام شد.');
    }
    return action == 'login' ? 'درخواست ورود ارسال شد.' : 'درخواست ثبت‌نام ارسال شد.';
  }
}

String? _messageFrom(Map value) {
  for (final key in ['message', 'msg', 'error', 'notice']) {
    final item = value[key];
    if (item is String && item.trim().isNotEmpty) return item;
  }
  return null;
}

class Novel {
  Novel({required this.title, this.description = '', this.imageUrl, this.permalink,
    this.category = '', this.raw = const {}});
  final String title;
  final String description;
  final String? imageUrl;
  final String? permalink;
  final String category;
  // Preserve the original fields to allow future mapping as the API evolves.
  final Map<String, dynamic> raw;

  factory Novel.fromJson(Map<String, dynamic> json) {
    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }
    return Novel(
      title: pick(['title', 'name', 'post_title']) ?? 'بدون عنوان',
      description: pick(['description', 'excerpt', 'content', 'post_content']) ?? '',
      imageUrl: pick(['image', 'thumbnail', 'image_url', 'featured_image', 'thumbnail_url']),
      permalink: pick(['permalink', 'url', 'link', 'post_url']),
      category: pick(['category', 'type', 'format']) ?? '',
      raw: json,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiClient _api = ApiClient();
  late Future<List<Novel>> _novels;
  String? _sessionUser; // Session-only display state; credentials are not retained.

  @override
  void initState() {
    super.initState();
    _novels = _api.getNovels();
  }

  Future<void> _reload() async {
    setState(() => _novels = _api.getNovels());
    try { await _novels; } catch (_) { /* FutureBuilder shows the error. */ }
  }

  Future<void> _openAuth() async {
    final result = await showDialog<String>(
      context: context, builder: (_) => AuthDialog(api: _api));
    if (result != null && mounted) setState(() => _sessionUser = result);
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('رمان VIP'),
              actions: [
                if (_sessionUser != null)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(child: Text(_sessionUser!))),
                IconButton(tooltip: _sessionUser == null ? 'ورود / ثبت‌نام' : 'خروج از نشست',
                  icon: Icon(_sessionUser == null ? Icons.person_outline : Icons.logout),
                  onPressed: () => _sessionUser == null
                      ? _openAuth()
                      : setState(() => _sessionUser = null)),
              ],
              bottom: const TabBar(tabs: [
                Tab(icon: Icon(Icons.picture_as_pdf_outlined), text: 'رمان‌های PDF (نمایشی)'),
                Tab(icon: Icon(Icons.menu_book_outlined), text: 'رمان‌های آنلاین'),
              ]),
            ),
            body: FutureBuilder<List<Novel>>(
              future: _novels,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorView(message: snapshot.error.toString(), onRetry: _reload);
                }
                final novels = snapshot.data ?? const <Novel>[];
                if (novels.isEmpty) return _EmptyView(onRetry: _reload);
                return TabBarView(children: [
                  _NovelList(novels: novels, pdfDemo: true),
                  _NovelList(novels: novels, pdfDemo: false),
                ]);
              },
            ),
          ),
        ),
      );
}

class _NovelList extends StatelessWidget {
  const _NovelList({required this.novels, required this.pdfDemo});
  final List<Novel> novels;
  final bool pdfDemo;

  bool _looksPdf(Novel n) {
    // DEMO ONLY: get_novels currently returns posts without reliable format metadata.
    final hint = '${n.category} ${n.title} ${n.raw['format'] ?? ''}'.toLowerCase();
    return hint.contains('pdf') || hint.contains('پی‌دی‌اف') || hint.contains('تمام');
  }

  @override
  Widget build(BuildContext context) {
    final shown = novels.where((n) => _looksPdf(n) == pdfDemo).toList();
    return Column(children: [
      if (pdfDemo)
        const MaterialBanner(
          content: Text('این دسته‌بندی صرفاً نمایشی است؛ API فعلی نوع/وضعیت PDF را تضمین نمی‌کند.'),
          leading: Icon(Icons.info_outline), actions: [SizedBox.shrink()],
        ),
      Expanded(child: shown.isEmpty
          ? Center(child: Text(pdfDemo
              ? 'موردی با برچسب PDF/تمام‌شده پیدا نشد. سایر پست‌ها در زبانه آنلاین هستند.'
              : 'هنوز رمانی برای نمایش نیست.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: shown.length,
              itemBuilder: (context, index) => NovelCard(novel: shown[index]))),
    ]);
  }
}

class NovelCard extends StatelessWidget {
  const NovelCard({required this.novel, super.key});
  final Novel novel;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => _openNovel(context, novel),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, height: 126, child: _Cover(url: novel.imageUrl)),
            Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(novel.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 7),
                Text(novel.description.replaceAll(RegExp(r'<[^>]*>'), ' ').trim(),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                const Text('مشاهده جزئیات در سایت', style: TextStyle(color: Colors.deepPurple)),
              ],
            ))),
          ]),
        ),
      );
}

class _Cover extends StatelessWidget {
  const _Cover({this.url});
  final String? url;
  @override
  Widget build(BuildContext context) {
    final uri = url == null ? null : Uri.tryParse(url!);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return _placeholder();
    return Image.network(uri.toString(), fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
      loadingBuilder: (context, child, progress) => progress == null
          ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)));
  }
  Widget _placeholder() => Container(color: Colors.black12,
    child: const Center(child: Icon(Icons.menu_book, size: 40)));
}

Future<void> _openNovel(BuildContext context, Novel novel) async {
  final uri = novel.permalink == null ? null : Uri.tryParse(novel.permalink!);
  if (uri == null || uri.scheme != 'https' || uri.host != 'roman-vip.ir') {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('پیوند امن و معتبر برای این رمان از API دریافت نشد.')));
    return;
  }
  // No purchase or premium entitlement is implemented in this client. Checkout/content remain on the site.
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بازکردن پیوند ممکن نشد.')));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off, size: 42), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 12), FilledButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
    ])));
}
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Text('پستی برای نمایش دریافت نشد.'), TextButton(onPressed: onRetry, child: const Text('بارگذاری مجدد')),
  ]));
}

class AuthDialog extends StatefulWidget {
  const AuthDialog({required this.api, super.key});
  final ApiClient api;
  @override
  State<AuthDialog> createState() => _AuthDialogState();
}
class _AuthDialogState extends State<AuthDialog> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false, _busy = false, _obscure = true;
  String? _error;

  @override
  void dispose() { _username.dispose(); _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.authenticate(_register ? 'register' : 'login', _username.text.trim(),
        _password.text, email: _register ? _email.text : null);
      // Deliberately do not persist credentials or invent/store an API token.
      if (mounted) Navigator.pop(context, _username.text.trim());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_register ? 'ساخت حساب' : 'ورود'),
    content: Form(key: _form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: _username, decoration: const InputDecoration(labelText: 'نام کاربری'),
        validator: (v) => v == null || v.trim().isEmpty ? 'نام کاربری را وارد کنید.' : null),
      if (_register) TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'ایمیل (در صورت نیاز API)'),
        validator: (v) => v == null || v.trim().isEmpty || v.contains('@') ? null : 'ایمیل معتبر وارد کنید.'),
      TextFormField(controller: _password, obscureText: _obscure,
        decoration: InputDecoration(labelText: 'گذرواژه', suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off))),
        validator: (v) => v == null || v.isEmpty ? 'گذرواژه را وارد کنید.' : null),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
        child: Text(_error!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 8), const Text('اطلاعات ورود فقط برای همین درخواست استفاده می‌شود و در برنامه ذخیره نمی‌شود.',
        style: TextStyle(fontSize: 12)),
    ]))),
    actions: [
      TextButton(onPressed: _busy ? null : () => setState(() { _register = !_register; _error = null; }),
        child: Text(_register ? 'قبلاً حساب دارم' : 'ثبت‌نام')),
      FilledButton(onPressed: _busy ? null : _submit,
        child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_register ? 'ثبت‌نام' : 'ورود')),
    ],
  );
}
