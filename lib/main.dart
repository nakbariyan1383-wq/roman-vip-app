import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String apiUrl = 'https://roman-vip.ir/app-api.php';
// شماره اختصاصی مدیر و نویسنده اپلیکیشن
const String adminPhoneNumber = '09904677308';

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

class Novel {
  Novel({
    required this.id,
    required this.title,
    this.author = 'نویسنده',
    this.summary = '',
    this.type = 'online',
    this.cover = '',
    this.content = '',
    this.pdfUrl = '',
    this.isVip = false,
  });

  final String id;
  final String title;
  final String author;
  final String summary;
  final String type;
  final String cover;
  final String content;
  final String pdfUrl;
  final bool isVip;

  factory Novel.fromJson(Map<String, dynamic> json) {
    return Novel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? json['name'] ?? json['post_title'] ?? 'بدون عنوان',
      author: json['author'] ?? 'نویسنده',
      summary: json['summary'] ?? json['description'] ?? json['excerpt'] ?? '',
      type: json['type'] ?? 'online',
      cover: json['cover'] ?? json['image'] ?? json['thumbnail'] ?? '',
      content: json['content'] ?? json['post_content'] ?? '',
      pdfUrl: json['pdf_url'] ?? json['download_url'] ?? json['permalink'] ?? '',
      isVip: json['is_vip'] == true || json['is_vip'] == 'true' || json['is_vip'] == 1,
    );
  }
}

class ApiService {
  static Future<List<Novel>> getNovels() async {
    final uri = Uri.parse('$apiUrl?action=get_novels');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      List rows = [];
      if (decoded is List) {
        rows = decoded;
      } else if (decoded is Map) {
        rows = decoded['novels'] ?? decoded['posts'] ?? decoded['data'] ?? [];
      }
      return rows.map((e) => Novel.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    throw Exception('خطای سرور (${response.statusCode})');
  }

  static Future<bool> addNovel(Map<String, dynamic> novelData) async {
    final uri = Uri.parse('$apiUrl?action=add_novel');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(novelData),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded['status'] == true;
    }
    return false;
  }

  static Future<Map<String, dynamic>> authWithPhone(String action, String phone, String password) async {
    final uri = Uri.parse('$apiUrl?action=$action');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'phone': phone, 'password': password}),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    return {'status': false, 'message': 'خطا در ارتباط با سرور'};
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Novel>> _novels;
  String? _currentUserPhone;

  @override
  void initState() {
    super.initState();
    _loadNovels();
  }

  void _loadNovels() {
    setState(() {
      _novels = ApiService.getNovels();
    });
  }

  void _openAuthDialog() {
    final phoneController = TextEditingController();
    final passController = TextEditingController();
    bool isRegister = false;
    bool isLoading = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(isRegister ? 'ثبت‌نام با شماره موبایل' : 'ورود به حساب'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'شماره موبایل (مثال: 09123456789)',
                      prefixIcon: Icon(Icons.phone_android),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'رمز عبور',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        setDialogState(() {
                          isRegister = !isRegister;
                          errorText = null;
                        });
                      },
                child: Text(isRegister ? 'قبلاً ثبت‌نام کرده‌اید؟ ورود' : 'حساب ندارید؟ ثبت‌نام'),
              ),
              FilledButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final phone = phoneController.text.trim();
                        final pass = passController.text.trim();

                        if (!RegExp(r'^09[0-9]{9}$').hasMatch(phone)) {
                          setDialogState(() => errorText = 'شماره موبایل ۱۱ رقمی معتبر وارد کنید (شروع با 09)');
                          return;
                        }
                        if (pass.length < 4) {
                          setDialogState(() => errorText = 'رمز عبور حداقل باید ۴ کاراکتر باشد');
                          return;
                        }

                        setDialogState(() {
                          isLoading = true;
                          errorText = null;
                        });

                        final res = await ApiService.authWithPhone(
                          isRegister ? 'register' : 'login',
                          phone,
                          pass,
                        );

                        if (res['status'] == true) {
                          if (mounted) {
                            setState(() => _currentUserPhone = phone);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(isRegister ? 'ثبت‌نام با موفقیت انجام شد' : 'خوش آمدید!')),
                            );
                          }
                        } else {
                          setDialogState(() {
                            isLoading = false;
                            errorText = res['message'] ?? 'عملیات ناموفق بود';
                          });
                        }
                      },
                child: isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(isRegister ? 'ثبت‌نام' : 'ورود'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddNovelDialog() {
    final titleController = TextEditingController();
    final authorController = TextEditingController();
    final summaryController = TextEditingController();
    final contentOrPdfController = TextEditingController();
    String type = 'online';
    bool isVip = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.edit_note, color: Color(0xff7546a8)),
                SizedBox(width: 8),
                Text('پنل مدیریت: ثبت رمان'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleController, decoration: const InputDecoration(labelText: 'عنوان رمان *')),
                  TextField(controller: authorController, decoration: const InputDecoration(labelText: 'نام نویسنده')),
                  TextField(controller: summaryController, decoration: const InputDecoration(labelText: 'خلاصه کوتاه داستان'), maxLines: 2),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    items: const [
                      DropdownMenuItem(value: 'online', child: Text('رمان آنلاین (متنی)')),
                      DropdownMenuItem(value: 'pdf', child: Text('رمان دانلودی (فایل PDF)')),
                    ],
                    onChanged: (val) => setDialogState(() => type = val!),
                    decoration: const InputDecoration(labelText: 'فرمت انتشار'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentOrPdfController,
                    decoration: InputDecoration(
                      labelText: type == 'online' ? 'متن رمان (پارت‌ها)' : 'لینک مستقیم دانلود فایل PDF',
                    ),
                    maxLines: type == 'online' ? 4 : 1,
                  ),
                  SwitchListTile(
                    title: const Text('رمان VIP (مخصوص مشترکین)'),
                    value: isVip,
                    onChanged: (val) => setDialogState(() => isVip = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
              FilledButton(
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('لطفاً عنوان رمان را وارد کنید.')),
                    );
                    return;
                  }
                  final data = {
                    'title': titleController.text.trim(),
                    'author': authorController.text.trim().isEmpty ? 'نویسنده' : authorController.text.trim(),
                    'summary': summaryController.text.trim(),
                    'type': type,
                    'is_vip': isVip,
                    'content': type == 'online' ? contentOrPdfController.text : '',
                    'pdf_url': type == 'pdf' ? contentOrPdfController.text.trim() : '',
                  };
                  Navigator.pop(context);
                  bool ok = await ApiService.addNovel(data);
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('رمان جدید با موفقیت منتشر شد!')),
                    );
                    _loadNovels();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('خطا در انتشار رمان.')),
                    );
                  }
                },
                child: const Text('انتشار در اپلیکیشن'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // بررسی اینکه آیا کاربر لاگین کرده مدیر (شما) است یا خیر
    final bool isAdmin = _currentUserPhone == adminPhoneNumber;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('رمان VIP'),
            centerTitle: true,
            actions: [
              if (_currentUserPhone != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      isAdmin ? 'مدیر: $_currentUserPhone' : _currentUserPhone!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isAdmin ? FontWeight.bold : FontWeight.normal,
                        color: isAdmin ? const Color(0xff7546a8) : Colors.black87,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(_currentUserPhone == null ? Icons.account_circle_outlined : Icons.logout),
                tooltip: _currentUserPhone == null ? 'ورود / عضویت' : 'خروج',
                onPressed: () {
                  if (_currentUserPhone == null) {
                    _openAuthDialog();
                  } else {
                    setState(() => _currentUserPhone = null);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('از حساب خارج شدید')),
                    );
                  }
                },
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.menu_book_outlined), text: 'رمان‌های آنلاین'),
                Tab(icon: Icon(Icons.picture_as_pdf_outlined), text: 'رمان‌های PDF'),
              ],
            ),
          ),
          body: FutureBuilder<List<Novel>>(
            future: _novels,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(snapshot.error.toString(), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _loadNovels, child: const Text('تلاش دوباره')),
                      ],
                    ),
                  ),
                );
              }
              final novels = snapshot.data ?? [];
              final onlineNovels = novels.where((n) => n.type == 'online').toList();
              final pdfNovels = novels.where((n) => n.type == 'pdf').toList();

              return TabBarView(
                children: [
                  _NovelListView(novels: onlineNovels, isPdfTab: false, onRefresh: _loadNovels),
                  _NovelListView(novels: pdfNovels, isPdfTab: true, onRefresh: _loadNovels),
                ],
              );
            },
          ),
          // این دکمه فقط و فقط برای شماره شما نمایش داده می‌شود
          floatingActionButton: isAdmin
              ? FloatingActionButton.extended(
                  onPressed: _showAddNovelDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('افزودن رمان (مدیر)'),
                  backgroundColor: const Color(0xff7546a8),
                  foregroundColor: Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class _NovelListView extends StatelessWidget {
  const _NovelListView({
    required this.novels,
    required this.isPdfTab,
    required this.onRefresh,
  });

  final List<Novel> novels;
  final bool isPdfTab;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (novels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isPdfTab ? Icons.picture_as_pdf : Icons.book, size: 54, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              isPdfTab ? 'هنوز رمان PDF ثبت نشده است.' : 'هنوز رمان آنلاینی ثبت نشده است.',
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRefresh, child: const Text('بروزرسانی صفحه')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: novels.length,
        itemBuilder: (context, index) {
          final novel = novels[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: const Color(0xff7546a8).withOpacity(0.15),
                child: Icon(isPdfTab ? Icons.picture_as_pdf : Icons.menu_book, color: const Color(0xff7546a8)),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      novel.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  if (novel.isVip)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('VIP', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('نویسنده: ${novel.author}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  if (novel.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(novel.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ],
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                if (isPdfTab) {
                  _handlePdfClick(context, novel);
                } else {
                  _showReaderDialog(context, novel);
                }
              },
            ),
          );
        },
      ),
    );
  }

  void _showReaderDialog(BuildContext context, Novel novel) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(novel.title),
          content: SingleChildScrollView(
            child: Text(
              novel.content.isNotEmpty ? novel.content : 'هنوز متنی برای این رمان ثبت نشده است.',
              style: const TextStyle(fontSize: 15, height: 1.8),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePdfClick(BuildContext context, Novel novel) async {
    if (novel.pdfUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لینک دانلود PDF برای این رمان وارد نشده است.')),
      );
      return;
    }
    final uri = Uri.tryParse(novel.pdfUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('باز کردن لینک دانلود ممکن نشد.')),
        );
      }
    }
  }
}
